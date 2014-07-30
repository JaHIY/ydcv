#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use autodie;
use 5.010;

use Carp;
use Data::Dumper;
use Encode;
use Getopt::Long;
use HTTP::Tiny;
use JSON;
use List::Util qw{first};
use Pod::Usage;
use Readonly;
use Term::ANSIColor;
use Term::ReadLine;
use URI::Escape;

Readonly my $API_NAME => q{YouDaoCV};
Readonly my $API_KEY  => q{659600698};
Readonly my $API_URL => qq{http://fanyi.youdao.com/openapi.do?keyfrom=${API_NAME}&key=${API_KEY}&type=data&doctype=json&version=1.1&q=};

sub get_json_for_definition_of {
    my ( $word ) = @_;
    my $http = HTTP::Tiny->new;
    my $response = $http->request('GET', $API_URL.uri_escape( $word ) );
    if ( $response->{'success'} ) {
        #print "$response->{'status'} $response->{'reason'}\n";
        if ( length $response->{'content'} ) {
            #print $response->{'content'};
            my $dict_hash_ref = JSON->new->utf8->decode( $response->{'content'} );
            #print Dumper($dict_hash_ref);
            return $dict_hash_ref;
        }
    }
    else {
        croak '错误：无法连接有道服务器！';
    }
}

sub colored_method {
    my ( $method ) = @_;
    my $print_content_only_sub_ref = sub {
        my ( $content, $color ) = @_;
            return $content;
    };
    if ( $method eq 'never' ) {
        return $print_content_only_sub_ref;
    }
    elsif ( $method eq 'auto' and ! -t *STDOUT ) {
        return $print_content_only_sub_ref;
    }
    else {
        return \&colored;
    }
}

sub print_explanation {
    my ( $dict_hash_ref, $option_hash_ref, $colored_methed_sub_ref ) = @_;
    print $colored_methed_sub_ref->( $dict_hash_ref->{'query'}, 'underline' );
    if ( exists $dict_hash_ref->{'basic'} ) {
        my $basic = $dict_hash_ref->{'basic'};
        if ( exists $basic->{'phonetic'} ) {
            printf " [%s]\n", $colored_methed_sub_ref->( $basic->{'phonetic'}, 'yellow' );
        }
        else {
            print "\n";
        }
        if ( exists $basic->{'explains'} ) {
            print $colored_methed_sub_ref->('  Word Explanation:', 'cyan'), "\n";
            my @explains = @{$basic->{'explains'}};
            for my $explain ( @explains ) {
                printf "     * %s\n", $explain;
            }
        }
        else {
            print "\n";
        }
    }
    elsif ( exists $dict_hash_ref->{'translation'} ) {
            print "\n", $colored_methed_sub_ref->('  Translation:', 'cyan'), "\n";
            my @translations = @{$dict_hash_ref->{'translation'}};
            for my $translation ( @translations ) {
                printf "     * %s\n", $translation;
            }
    }
    else {
        print "\n";
    }

    if ( !$option_hash_ref->{'simple'} ) {
        if ( exists $dict_hash_ref->{'web'} ) {
            print "\n", $colored_methed_sub_ref->('  Web Reference:', 'cyan'), "\n";
            my @web_references = $option_hash_ref->{'full'} ? @{$dict_hash_ref->{'web'}} : @{$dict_hash_ref->{'web'}}[0..2];
            for my $web_reference ( @web_references ) {
                #print Dumper $web_reference;
                printf "     * %s\n       %s\n", $colored_methed_sub_ref->( $web_reference->{'key'}, 'yellow' ), join( '; ', map { $colored_methed_sub_ref->($_, 'magenta') } @{$web_reference->{'value'}} );
            }
        }
    }
    print "\n";
}

sub look_up {
    my ( $word, $option_hash_ref ) = @_;
    my $dict_hash_ref = get_json_for_definition_of( $word );
    my $error_code = $dict_hash_ref->{'errorCode'};
    #$error_code = 50;
    if ( $error_code == 0 ) {
        print_explanation( $dict_hash_ref, $option_hash_ref, colored_method($option_hash_ref->{'color'}) );
    }
    else {
        croak sprintf( '错误代码：%d，%s',
                                        $error_code,
                                        $error_code == 20 ? '要翻译的文本过长！'  :
                                        $error_code == 30 ? '无法进行有效的翻译！':
                                        $error_code == 40 ? '无效的key！'         :
                                        $error_code == 50 ? '不支持的语言类型！'  :
                                        $error_code == 60 ? '无词典结果！'        :
                                                            '未知错误！'
        );
    }
}

sub main {
    binmode *STDIN, ':encoding(utf8)';
    binmode *STDOUT, ':encoding(utf8)';
    my %option_of = ( color  => 'auto',
                      help   => 0,
                      full   => 0,
                      man    => 0,
                      simple => 0,
                    );
    my @color_option = ( 'always',
                         'auto',
                         'never',
                       );
    GetOptions( 'color=s'  => \$option_of{'color'},
                'help|h'   => \$option_of{'help'},
                'full|f'   => \$option_of{'full'},
                'man'      => \$option_of{'man'},
                'simple|s' => \$option_of{'simple'},
    );
    if ( $option_of{'help'} ) {
        pod2usage 1;
    }
    if ( $option_of{'man'} ) {
        pod2usage(-verbose => 2);
    }
    if ( !first { $option_of{'color'} eq $_ } @color_option ) {
        croak "错误：不存在$option_of{'color'}选项！";
    }
    if ( @ARGV == 0 ) {
        my $term = Term::ReadLine->new('YouDao Console Version');
        $term->ornaments(0);
        while ( defined( my $word = $term->readline('> ') ) ) {
            look_up( $word, \%option_of );
            $term->addhistory($word);
        }
    } else {
        for my $word ( @ARGV ) {
            look_up( $word, \%option_of );
        }
    }
}

main;

__END__

=head1 NAME

YouDao Console Version rewriten in perl

=head1 SYNOPSIS

ydcv [options] [string ...]

Options:

--full|-f        print full web reference, only the first 3 results will be printed without this flag.

--simple|-s      only show explainations.

--color          colorize the output. Default to 'auto' or can be 'never' or 'always'.

--help|-h        print help message.

--man            full documentation.

=head1 OPTIONS

=over

=item B<--full|-f>

print full web reference,
only the first 3 results will be printed without this flag.

=item B<--simple|-s>

only show explainations.

=item B<--color>

colorize the output.
Default to 'auto' or can be 'never' or 'always'.

=item B<--help|-h>

print help message and exit.

=item B<--man>

print full documentation and exit.

=back

=head1 DESCRIPTION

Simple wrapper for Youdao online translate (Chinese <-> English) service API, as an alternative to the StarDict Console Version.

=cut
