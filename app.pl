#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: app.pl
#
#        USAGE: ./app.pl  
#
#  DESCRIPTION: js/css文件合并代理服务，支持版本和缓存管理，自动压缩
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Baboo (8boo.net), baboo.wg@gmail.com
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 2015/05/27 17时02分12秒
#     REVISION: ---
#===============================================================================

use Mojolicious::Lite;
use Mojo::UserAgent;
use Mojo::URL;
use Mojo::Util qw/decode/;
use CSS::Minifier;
use JavaScript::Minifier;
use utf8;

my $ua = Mojo::UserAgent->new(
    max_redirects => 3,
    connect_timeout => 60,
    inactivity_timeout => 60
);

my %cache = ();

get '/proxy/cache_list' => sub {
    my $c = shift;
   
    my $json = {};
    
    for my $key (keys %cache) {
        my $remain_time = $cache{$key}{expire_time} - time;
        next if $remain_time < 0;
        $json->{$key} = {
            cache_time => $remain_time,
            content_length => length($cache{$key}{content}),
        };
    }
    $c->render(json => $json);
};

get '/proxy/#type/*resource_page' => [ type => qr/(?:js|css)(?:\.\w+)?(?:\.\d+)?/i ] => sub {
    my $c = shift; 
    
    my $url = Mojo::URL->new('http://' . $c->param('resource_page'));
    my $config_info = $c->param('type');

    my ($type, $version, $cache_time) = split /\./, $config_info;
    
    $cache_time //= 3600;

    my $cache_key = "$type.$version/$url";

    my ($tag_name, $attr_name, $content_type, $minify) = $type eq 'js' 
        ? ('script', 'src', 'application/javascript;charset=utf8', \&JavaScript::Minifier::minify) 
        : ('link', 'href', 'text/css;charset=utf8', \&CSS::Minifier::minify);

    if ($cache{$cache_key} 
        && time - $cache{$cache_key}{time} <= $cache_time 
        && time < $cache{$cache_key}{expire_time}
    ) {
        $c->res->headers->content_type($content_type);
        $c->res->headers->cache_control("public, max-age=$cache_time");
        return $c->render(text => $cache{$cache_key}{content});
    }

    $c->inactivity_timeout(300);

    $c->app->log->debug("Load $url");

    my $page_tx = $c->tx;

    $ua->get($url => sub {

        my ($ua, $tx) = @_;
        
        my $res = $tx->success;

        unless ($res) {
            return $c->render(text => "Resource page load fail:[$url]", status => 404);
        }

        my $dom = $res->dom;
        my @all_content = ();
        my $request_count = 0;
        my @fail_resources = (); 

        $dom->find($tag_name)->each(sub {
            my ($elem, $num) = @_;

            if (my $src = $elem->attr($attr_name)) {
                return if $src ~~ m{/proxy/};

                my $resource_url = Mojo::URL->new($src)->to_abs($url); 

                $request_count++;

                $c->app->log->debug("Load $resource_url");
                $ua->get($resource_url, sub {
                    my ($ua, $tx) = @_;
                    
                    $c->app->log->debug("Load ok $resource_url");
                    if (my $res = $tx->success) {
                        my $body = $res->body;
                        if ($body) {
                            eval {
                                $body = $minify->(input => $body);
                            };

                            $c->app->log->error("Minify $type error:$@. [$resource_url]") if $@;
                        }
                        $body = decode('utf8', $body);

                        if ($type eq 'css') {
                            $body =~ s{url\((.+?)\)}{
                                my $src = $1;
                                unless ($src ~~ /^http/) {
                                    $src = Mojo::URL->new($src)->to_abs($resource_url) . ''; 
                                }
                                "url($src)";
                            }xsemgi;
                        }

                        $body = "/*$resource_url*/\n$body";
                        $all_content[$num - 1] = $body;
                    } else {
                        push @fail_resources, $resource_url;
                        $c->app->log->error("Load resource error:[$resource_url]", $tx->error->{message});
                    }

                    if (--$request_count == 0) {
                        return response(
                            $c, $page_tx, \@fail_resources, join("\n", @all_content), 
                            $content_type, $cache_key, $cache_time
                        );
                    }
                });
            } 
        });

        if ($request_count == 0) {
            return response(
                $c, $page_tx, \@fail_resources, join("\n", @all_content), 
                $content_type, $cache_key, $cache_time
            );
        }
    });

    $c->render_later;
};

sub response {
    my ($c, $tx, $fail_resources, $content, $content_type, $cache_key, $cache_time) = @_;

    if (@$fail_resources) {
        my $warning = sprintf("/*Warning: There %d resource load fail:%s*/", 
            scalar(@$fail_resources), join(",", @$fail_resources)
        );

        $content = "$warning\n$content";
    }

    $cache{$cache_key} = {
        content => $content,
        time => time,
        expire_time => time + $cache_time,
    };

    $tx->res->headers->content_type($content_type);
    $tx->res->headers->cache_control("public, max-age=$cache_time");
    return $c->render(text => $content);
}

app->secrets(['^_SM_^']);
app->config(hypnotoad => {listen => ['http://*:9001'], workers => 4});
app->start;
