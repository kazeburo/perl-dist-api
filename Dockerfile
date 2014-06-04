FROM rsrchboy/perl-v5.18:latest
RUN apt-get -y install memcached 
RUN apt-get -y build-dep libcrypt-ssleay-perl
RUN cpanm -n Kossy CPAN::Perl::Releases HTTP::Tiny IO::Socket::SSL Cache::Memcached::Fast::Safe Proclet Plack Plack::Builder::Conditionals Starlet List::Util Getopt::Long Test::TCP
RUN mkdir -p /opt/perl-dist-api
ADD ./server.pl /opt/perl-dist-api/server.pl
ADD ./cpanfile /opt/perl-dist-api/cpanfile
RUN cpanm -n --installdeps /opt/perl-dist-api
EXPOSE 80
CMD ["perl","/opt/perl-dist-api/server.pl","--port","80"]

