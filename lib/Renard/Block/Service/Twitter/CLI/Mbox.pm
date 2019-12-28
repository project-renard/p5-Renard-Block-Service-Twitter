use Renard::Incunabula::Common::Setup;
package Renard::Block::Service::Twitter::CLI::Mbox;
# ABSTRACT: Convert Tweet JSON to mbox

use Mu;
use Path::Tiny;
use JSON::MaybeXS;
use Mail::Message;
use Mail::Box::Mbox;
use Lingua::Sentence;
use Twitter::API::Util qw(timestamp_to_time);
use DateTime;
use DateTime::Format::Mail;

use CLI::Osprey;

option tweet_jsonl_file => (
	is => 'ro',
	format => 's',
	required => 1,
);

option mbox_file => (
	is => 'ro',
	format => 's',
	required => 1,
);

lazy _tweet_jsonl_path => method() {
	path($self->tweet_jsonl_file);
};

method run() {
	my $fh = $self->_tweet_jsonl_path->openr_utf8;
	mkdir $self->mbox_file;
	my $folder = Mail::Box::Mbox->new(
		folder => $self->mbox_file,
		access => 'w',
	);
	my $splitter = Lingua::Sentence->new('en');

	while( defined(my $line = <$fh>) ) {
		my $tweet = decode_json( $line );
		my $tweet_id = $tweet->{id};
		my $tweet_text = $tweet->{full_text};
		my $tweet_reply = $tweet->{in_reply_to_status_id};
		my ($user_name, $screen_name, $user_id, $user_image) = @{ $tweet->{user} }{qw(
			name screen_name id profile_image_url_https
		)};
		my $url = "https://twitter.com/@{[ $screen_name ]}/status/@{[ $tweet_id ]}";

		if( exists $tweet->{extended_entities}{media} ) {
			for my $media (@{$tweet->{extended_entities}{media}}) {
				#use DDP; p $media->{media_url_https};
			}
		}

		my $tweet_without_prefix = $tweet_text =~ s/^(\@\S+\s+)+//gr;
		my @sentences = $splitter->split_array($tweet_without_prefix);
		my $subject_string;
		my @subject;
		my $subject_length = 0;
		while(@sentences && $subject_length < 120) {
			my $next_sent = shift @sentences;
			$subject_length += length $next_sent;
			push @subject, $next_sent;
		}
		$subject_string .= join ' ', @subject;
		$subject_string =~ s/\n/ /g;


		my $tweet_offset = 0;
		if( exists $tweet->{entities}{urls} ) {
			for my $url_entity (@{ $tweet->{entities}{urls} }) {
				substr(
					$tweet_text,
					$tweet_offset + $url_entity->{indices}[0],
					$url_entity->{indices}[1] - $url_entity->{indices}[0],
				) = $url_entity->{expanded_url};
				$tweet_offset += length($url_entity->{expanded_url}) - length($url_entity->{url})
			}
		}

		if( exists $tweet->{is_quote_status} && $tweet->{is_quote_status}) {
			$tweet_text .= "\n";
			$tweet_text .= "On @{[ $tweet->{quoted_status}{created_at} ]}, @{[ $tweet->{quoted_status}{user}{name} ]} said:";
			$tweet_text .= "\n";
			$tweet_text .= $tweet->{quoted_status}{full_text} =~ s/^/> /gmr;
		}


		my $dt = DateTime->from_epoch( epoch => timestamp_to_time( $tweet->{created_at} ) );

		my $message = Mail::Message->build(
			From => "@{[ $user_name ]} <@{[ $screen_name ]}\@twitter.com>",
			Date => DateTime::Format::Mail->format_datetime( $dt ),
			'Message-ID' => "<@{[ $tweet_id ]}\@twitter.com>",
			Subject => $subject_string,
			'X-Twitter-URL' => "<$url>",
			defined $tweet_reply
				? (
					'In-Reply-To' => "<@{[ $tweet_reply ]}\@twitter.com>",
				)
				: (),
			data => $tweet_text,
		);

		$folder->addMessage( $message );
	}
	$folder->close;
}

1;
