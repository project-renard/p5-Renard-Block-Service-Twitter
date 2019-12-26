use Renard::Incunabula::Common::Setup;
package Renard::Block::Service::Twitter::CLI;
# ABSTRACT: CLI client for Twitter

use Mu;
use YAML::XS;
use JSON::XS;
use Twitter::API;
use WWW::Mechanize::Chrome;
use Web::Scraper;
use WWW::Mechanize;
use Set::Scalar;

use CLI::Osprey;

option url => ( is => 'ro', format => 's', required => 1 );


lazy url_name => method() {
	(URI->new( $self->url )->path_segments)[-3];
};

lazy url_id => method() {
	(URI->new( $self->url )->path_segments)[-1];
};

lazy stream_container_scraper => method() {
	scraper {
		process '//div[contains(@class,"stream-container")]',
			'max_position' => '@data-max-position',
			'min_position' => '@data-min-position';
	};
};
		#process 'article', 'articles[]' => scraper {
			#process "div", text => 'TEXT';
		#};

lazy user_agent => method() {
	WWW::Mechanize::Chrome->new(
		port => 9090,
		tab => 'current',
		#launch_exe => $^X,
		#launch_arg => [ './bin/cef.pl' ],
	);
};

lazy config => method() {
	YAML::XS::LoadFile('../config.yml');
};

lazy client => method() {
	my $client = Twitter::API->new_with_traits(
		traits              => [ qw/ Enchilada RateLimiting / ],
		consumer_key        => $self->config->{consumer}{key},
		consumer_secret     => $self->config->{consumer}{secret},
		access_token        => $self->config->{access}{token},
		access_token_secret => $self->config->{access}{secret},
	);
};

method scroll_to_end() {
	$self->user_agent->wait_until_visible( selector => '#permalink-overlay', sleep => 1 );

	{
		no warnings 'redefine';
		local *WWW::Mechanize::Chrome::_scroll_to_bottom = sub {
			my $self = shift;
			$self->eval( q{
				var po = document.getElementById('permalink-overlay');
				po.scrollBy(0,po.scrollHeight + 200);
			} );
		};

		local *WWW::Mechanize::Chrome::_get_body_height = sub {
			my $self = shift;

			my ($height) = $self->eval( q|document.getElementById('permalink-overlay').scrollHeight| );
			return $height;
		};

		1 while( $self->user_agent->infinite_scroll(1) );
	}

}

method show_sensitive_threads() {
	eval {
		$self->user_agent->click({
			xpath => q|//button[contains(@class, 'ThreadedConversation-showMoreThreadsPrompt')]|,
			intrapage => 1
		});
	}
}

method show_more_replies() {
	my @more_replies = ( selector => q|a.ThreadedConversation-moreRepliesLink| );
	while( eval { my ($dom) = $self->user_agent->selector( $more_replies[1] ) } ) {
		eval {
			$self->user_agent->click( { @more_replies , intrapage => 1 } );
		}
	}
}

method load_page( $url ) {
	return if $self->uri_visited->{ $url };
	$self->user_agent->get( $url );
	sleep 2;

	$self->scroll_to_end;
	$self->show_sensitive_threads;
	$self->scroll_to_end;
	$self->show_more_replies;
	sleep 1;

	$self->uri_visited->{ $url } = 1;
}

has uri_visited => (
	is => 'rw',
	default => sub { +{} },
);

lazy uri_set => method() {
	Set::Scalar->new;
};

method run() {
	my $me   = $self->client->verify_credentials;
	#my $user = $self->client->show_user('twitter');
	#use DDP; p $user;
	#my $status = $self->client->lookup_statuses('1202663202997170176', { tweet_mode => 'extended' } );

	my @q;

	if( -f 'uri.yml' ) {
		my $data = YAML::XS::LoadFile('uri.yml');
		if( $data ) {
			@q = @{ $data->{queue} };
			$self->uri_visited( $data->{visit} );
			$self->uri_set->insert( @{ $data->{set} } );
		}
	}

	push @q, $self->url;
	$self->uri_set->insert( $self->url );
	while( @q ) {
		my $url = shift @q;

		$self->load_page( $url );

		my @tweets = $self->user_agent->selector( 'a.tweet-timestamp' );
		my @tweet_uri = map { URI->new_abs( $_->get_attribute('href'), 'https://twitter.com/')->as_string }  @tweets;
		for my $tweet_uri (@tweet_uri) {
			push @q, $tweet_uri unless $self->uri_set->has($tweet_uri);
		}
		$self->uri_set->insert( @tweet_uri );

		YAML::XS::DumpFile('uri.yml~', {
			set => [ $self->uri_set->elements ],
			visit => $self->uri_visited,
			queue => \@q,
		});
		if( -s 'uri.yml~' ) {
			rename 'uri.yml~', 'uri.yml';
		} else {
			die "Truncated file";
		}
	}


	#my @nodes = $self->user_agent->xpath('//span[@data-tweet-stat-count]');

	# $x("//div[starts-with(normalize-space(text()),'Show additional replies, including those that may contain offensive content')]/..//span[text()='Show']")[0].click()
	# $x("//button[contains(@class, 'ThreadedConversation-showMoreThreadsPrompt')]")[0].click()
	# $x("//a[contains(@class, 'ThreadedConversation-moreRepliesLink')]").forEach(function(link) { link.click() } )

	# $x("//div[@id='permalink-overlay']")[0].scrollBy(0,document.body.scrollHeight + 200)

	#require Carp::REPL; Carp::REPL->import('repl'); repl();#DEBUG
}

method conversation_uri( $min_position ) {
	my $conversation_uri = "https://twitter.com/i/@{[ $self->url_name ]}/conversation/@{[ $self->url_id ]}?include_available_features=1&include_entities=1&max_position=@{[ $min_position ]}&reset_error_state=false";
}

method temp() {
	my $data = $self->stream_container_scraper->scrape( $self->user_agent->response );
	$data->{has_more_items} = 1;
	$data->{html} = $self->user_agent->content;

	use HTML::FormatText;
	use HTML::TreeBuilder;
	use HTML::TreeBuilder::XPath;
	my $formatter = HTML::FormatText->new(leftmargin => 0, rightmargin => 200);
	while( $data->{has_more_items} ) {
		my $html = $data->{html};
		my $tree = HTML::TreeBuilder::XPath->new_from_content( $html );
		print $formatter->format($tree);

		$self->user_agent->get( $self->conversation_uri( $data->{min_position} ) );
		my $json_r = decode_json( $self->user_agent->content );

		$data->{html} = $json_r->{items_html};
		$data->{min_position} = $json_r->{min_position};
		$data->{has_more_items} = $json_r->{has_more_items};
	}
}

1;
