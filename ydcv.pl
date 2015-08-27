#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use autodie;
use 5.010;

use Carp;
use Encode::Locale;
use Encode qw(decode);
use Getopt::Long;
use HTTP::Tiny;
use JSON;
use List::Util qw(first);
use Pod::Usage;
use Term::ANSIColor;
use Term::ReadLine;
use Text::Wrap qw(wrap);
use URI;
use URI::QueryParam;

my $API_NAME     = q{YouDaoCV};
my $API_KEY      = q{659600698};
my $API_BASE_URL = q{http://fanyi.youdao.com/openapi.do};
my $API_URI      = do {
    my %query_params = (
        keyfrom => $API_NAME,
        key     => $API_KEY,
        type    => 'data',
        doctype => 'json',
        version => '1.1',
    );
    my $api_uri = URI->new( $API_BASE_URL );
    $api_uri->query_form_hash( \%query_params );
    $api_uri;
};
my $SPACE = q{ };
my %WRAP_CONFIG = (
    explanation => {
        initial_tab => $SPACE x 2,
        subsequent_tab => ( $SPACE x 5 ) . '*' . $SPACE,
    },
    reference_item => {
        initial_tab => ( $SPACE x 5 ) . '*' . $SPACE,
        subsequent_tab => $SPACE x 7,
    },
    reference => {
        initial_tab => $SPACE x 2,
        subsequent_tab => '',
    },
);

sub build_api_url_with {
    my ( $query_params_ref ) = @_;
    my $api_uri = $API_URI->clone;
    map { $api_uri->query_param_append( $_, $query_params_ref->{ $_ } ) } keys %{ $query_params_ref };
    return $api_uri;
}

sub get_json_for_definition_of {
    my ( $word ) = @_;
    my $http = HTTP::Tiny->new;
    my $response = $http->request( 'GET', build_api_url_with( {
                q => $word,
            } ) );
    if ( $response->{'success'} ) {
        if ( length $response->{'content'} ) {
            my $dict_hash_ref = JSON->new->utf8->decode( $response->{'content'} );
            return $dict_hash_ref;
        }
    }
    else {
        croak '错误：无法连接有道服务器！';
    }
}

sub print_content_only {
    my ( $content ) = @_;
    return $content;
}

sub colored_method {
    my ( $method ) = @_;
    if ( $method eq 'never' ) {
        return \&print_content_only;
    }
    elsif ( $method eq 'auto' and not -t *STDOUT ) {
        return \&print_content_only;
    }
    else {
        return \&colored;
    }
}

sub wrap_text {
    my ( $config_name, @text ) =  @_;

    croak "Cannot find the wrap config for `$config_name`" if not defined $WRAP_CONFIG{ $config_name };

    return wrap( ( @{ $WRAP_CONFIG{ $config_name } }{qw/initial_tab subsequent_tab/} ), @text );
}

sub print_explanation {
    my ( $dict_hash_ref, $option_hash_ref, $colored_methed_sub_ref ) = @_;
    print $colored_methed_sub_ref->( $dict_hash_ref->{'query'}, 'underline' );
    if ( defined $dict_hash_ref->{'basic'} ) {
        my $basic = $dict_hash_ref->{'basic'};
        if ( defined $basic->{'phonetic'} ) {
            printf " [%s]\n", $colored_methed_sub_ref->( $basic->{'phonetic'}, 'yellow' );
        } else {
            print "\n";
        }

        if ( defined $basic->{'explains'} ) {
            my @explains = (
                $colored_methed_sub_ref->( 'Word Explanation:', 'cyan' ),
                @{ $basic->{'explains'} },
            );
            print wrap_text( 'explanation', join( "\n", @explains  ) );
            print "\n";
        }

    } elsif ( defined $dict_hash_ref->{'translation'} ) {
        print "\n";
        my @translations = (
            $colored_methed_sub_ref->( 'Translation:', 'cyan' ),
            @{ $dict_hash_ref->{'translation'} },
        );
        print wrap_text( 'explanation', join( "\n", @translations ) );
        print "\n";
    }


    if ( not $option_hash_ref->{'simple'} ) {
        if ( defined $dict_hash_ref->{'web'} ) {
            print "\n";
            my @web_references = (
                $colored_methed_sub_ref->( 'Web Reference:', 'cyan' ),
            );
            my @web_text = $option_hash_ref->{'full'} ? @{ $dict_hash_ref->{'web'} } : @{ $dict_hash_ref->{'web'} }[0 .. 2];
            for my $web ( @web_text ) {
                my $key = $colored_methed_sub_ref->( $web->{'key'}, 'yellow' );
                my $value = join( '; ', map { $colored_methed_sub_ref->( $_, 'magenta' ) } @{ $web->{'value'} } );
                push @web_references, wrap_text( 'reference_item', join( "\n", $key, $value ) );
            }
            print wrap_text( 'reference', join "\n", @web_references );
        }
    }
    print "\n";
}

sub look_up {
    my ( $word, $option_hash_ref ) = @_;
    my $dict_hash_ref = get_json_for_definition_of($word);
    my $error_code    = $dict_hash_ref->{'errorCode'};
    if ( $error_code == 0 ) {
        print_explanation( $dict_hash_ref, $option_hash_ref, colored_method( $option_hash_ref->{'color'} ) );
    }
    else {
        croak sprintf(
            '错误代码：%d，%s', $error_code,
            $error_code == 20   ? '要翻译的文本过长！'
            : $error_code == 30 ? '无法进行有效的翻译！'
            : $error_code == 40 ? '无效的key！'
            : $error_code == 50 ? '不支持的语言类型！'
            : $error_code == 60 ? '无词典结果！'
            :                     '未知错误！'
        );
    }
}

sub main {
    my @argv = map { decode( locale => $_, 1 ) } @_;
    if ( -t ) {
        binmode STDIN, ':encoding(console_in)';
        binmode STDOUT, ':encoding(console_out)';
        binmode STDERR, ':encoding(console_out)';
    }
    my %option_of = (
        color => 'auto',
    );
    my @color_option = qw/
        always
        auto
        never
        /;

    my $getopt = Getopt::Long::Parser->new;
    croak 'Cannot parse options!' if not $getopt->getoptionsfromarray(
        \@argv,
        \%option_of,
        'color=s',
        'help|h',
        'full|f',
        'man',
        'simple|s',
    );

    if ( $option_of{'help'} ) {
        pod2usage 1;
    }
    if ( $option_of{'man'} ) {
        pod2usage( -verbose => 2 );
    }
    if ( !first { $option_of{'color'} eq $_ } @color_option ) {
        croak "错误：不存在$option_of{'color'}选项！";
    }
    if ( @argv == 0 ) {
        my $term = Term::ReadLine->new('YouDao Console Version');
        $term->ornaments(0);
        while ( defined( my $word = decode( locale => $term->readline('> '), 1 ) ) ) {
            look_up( $word, \%option_of );
            $term->addhistory($word);
        }
    }
    else {
        for my $word ( @argv ) {
            look_up( $word, \%option_of );
        }
    }
}

main( @ARGV );

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
