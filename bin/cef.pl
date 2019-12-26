#!/usr/bin/env perl
# PODNAME: cef.pl
# ABSTRACT: start CEF

use FindBin;
use lib "$FindBin::Bin/../lib";

use Modern::Perl;
use Renard::API::CEF;

sub main {
	if( 0 == fork ) {
		my $main_args = Renard::API::CEF::MainArgs->new([ @ARGV ]);
		my $settings = Renard::API::CEF::Settings->new_with_default_settings;
		$settings->no_sandbox(1);
		$settings->remote_debugging_port(9090);
		my $app = Renard::API::CEF::App->new;
		my $exit_code = Renard::API::CEF::_Global::CefExecuteProcess($main_args, $app);
		return $exit_code if $exit_code >= 0;
		Renard::API::CEF::_Global::CefInitialize($main_args, $settings, $app);

		my $url = 'about:blank';
		#my $url = 'https://slashdot.org/';
		my $browser = Renard::API::CEF::App::create_client(0, $url);

		Renard::API::CEF::_Global::CefRunMessageLoop();
	}
}

main;
