use Renard::Incunabula::Common::Setup;
package Renard::Block::Service::Twitter::CLI;
# ABSTRACT: CLI client for Twitter

use Mu;
use CLI::Osprey;

subcommand crawl => 'Renard::Block::Service::Twitter::CLI::Crawl';

subcommand mbox => 'Renard::Block::Service::Twitter::CLI::Mbox';

method run() {
	...
}

1;
