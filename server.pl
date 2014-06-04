#!/usr/bin/perl

package ApiWeb;

use strict;
use warnings;
use utf8;
use 5.16.0;
use Kossy;
use CPAN::Perl::Releases;
use HTTP::Tiny;
use Cache::Memcached::Fast::Safe;


sub perl_release {
    my ($self, $version) = @_;

    my $dist_path;
    my @methods = qw/perl_releases_mod perl_releases_metacpan perl_releases_search_cpan/;
    for my $method ( @methods ) {
        eval {
            $dist_path = $self->can($method)->($self,$version);
        };
        last if $dist_path;
        warn "WARN: Cannot find the tarball for perl-$version: $@\n" if $@;
    }
    die "ERROR: Cannot find the tarball for perl-$version\n" if !$dist_path;

    return $dist_path;
}

sub perl_releases_mod {
    my ($self, $version) = @_;
    my $tarballs = CPAN::Perl::Releases::perl_tarballs($version);

    my $x = (values %$tarballs)[0];

    if ($x) {
        return $x;
    }
    die "not found by CPAN::Perl::Releases\n";
}

sub perl_releases_search_cpan {
    my ($self, $version) = @_;
    my $html = http_get($self,"http://search.cpan.org/dist/perl-${version}");
    my ($dist_path) =
        $html =~ m[<a href="/CPAN/authors/id/(.+/perl-\Q${version}\E.tar.(?:gz|bz2))">Download</a>];
    die "not found on search.cpan.org\n" if !$dist_path;
    return $dist_path;
}

sub perl_releases_metacpan {
    my ($self, $version) = @_;
    my $html = http_get($self,'https://metacpan.org/pod/distribution/perl/pod/perl.pod');
    my ($version_url) =
        $html =~ m[<option +value="(/module/.+?/perl-\Q${version}\E/pod/perl\.pod)">];
    die "not found the perl-$version on metacpan\n" unless $version_url;
    $html = http_get($self,'https://metacpan.org/'.$version_url);
    my ($dist_path) =
        $html =~ m[\<a href="http://cpan\.metacpan\.org/authors/id/(.+/perl-\Q${version}\E\.tar\.(?:gz|bz2))"\>];
    die "not found on metacpan\n" if !$dist_path;
    return $dist_path;
}

my $memd; 
sub http_get {
    my ($self,$url) = @_;
    $memd ||= Cache::Memcached::Fast::Safe->new({
        servers => ['127.0.0.1:'.$self->{memcached}],
        utf8 => 1,
    });
    my $response = $memd->get_or_set($url,sub {
                                        my $http = HTTP::Tiny->new(timeout=>10);
                                        return $http->get($url); 
                                    }, 600);
    if ($response->{success}) {        
        return $response->{content};
    } else {
        die "Cannot get content from $url: $response->{status} $response->{reason}\n";
    }
}

get "/" => sub {
    my ( $self, $c )  = @_;
    $c->response->body("Please access to /v/{perl-version}. eg /v/5.18.2\n");
};

get '/v/:version' => sub {
    my ( $self, $c )  = @_;
    my $path;
    eval {
        $path = $self->perl_release($c->args->{version});
    };
    if ($@) {
        $c->halt('500',$@);
    }
    $c->response->body($path);
};


1;

package main;

use strict;
use warnings;
use utf8;
use 5.16.0;
use Proclet;
use Plack::Loader;
use Plack::Builder;
use Plack::Builder::Conditionals;
use Getopt::Long;
use List::Util qw/first/;
use Test::TCP;

my $port = 5111;
Getopt::Long::Configure ("no_ignore_case");
GetOptions(
    "p|port=s" => \$port,
);

my $memcached = first { -f $_ } qw!/usr/local/bin/memcached /usr/bin/memcached!;
if ( !$memcached ) {
    die "couldnot find memcached";
}
my $memcached_port = empty_port();

my $proclet = Proclet->new();

$proclet->service(
      code => [$memcached,'-u','nobody','-U','0','-l','127.0.0.1','-p',$memcached_port],
      tag => 'memcached'
);

$proclet->service(
      code => sub {
          my $app = ApiWeb->new(root_dir=>"./",memcached=>$memcached_port)->psgi();
          $app = builder {
              enable match_if addr([qw/127.0.0.1/]), 'ReverseProxy';
              $app;
          };
          my $loader = Plack::Loader->load(
              'Starlet',
              port => $port,
              host => 0,
              max_workers => 30,
          );
          $loader->run($app);

      },
      tag => 'web',
);

$proclet->run;

