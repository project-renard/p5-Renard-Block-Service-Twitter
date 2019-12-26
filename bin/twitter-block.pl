#!/usr/bin/env perl
# PODNAME: twitter-block.pl
# ABSTRACT: Twitter CLI

use FindBin;
use lib "$FindBin::Bin/../lib";

use Modern::Perl;
use Renard::Block::Service::Twitter::CLI;

sub main {
	Renard::Block::Service::Twitter::CLI
		->new_with_options
		->run;
}

main;
