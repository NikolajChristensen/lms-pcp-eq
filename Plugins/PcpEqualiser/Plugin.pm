package Plugins::PcpEqualiser::Plugin;

# Live 10-band equaliser for piCorePlayer players.
#
# piCorePlayer's own equaliser page only applies the sliders when you press
# Test, and only keeps them over a reboot when you press Save. This plugin
# serves a page (plugins/PcpEqualiser/index.html) whose sliders are applied
# while you drag them; Save keeps them, Reset goes back to the saved ones. It
# talks to each player through the same requests pCP's page sends
# (cgi-bin/xtras_alsaequal.cgi), so nothing needs installing on the players.
#
# The page reaches the players only through the JSON routes below, which
# only ever contact the IP address of a player connected to this server.

use strict;
use warnings;
use base qw(Slim::Plugin::Base);

use JSON::XS::VersionOneAndTwo;
use URI::Escape qw(uri_unescape);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Player::Client;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log = Slim::Utils::Log->addLogCategory({
    category     => 'plugin.pcpequaliser',
    defaultLevel => 'WARN',
    description  => 'PLUGIN_PCPEQUALISER',
});

# originals: each player's values as first seen, before this plugin changed
#   anything, so they can always be restored: { <player id> => { values, ... } }
# saved: the values last saved on each player. pCP's page shows what is
#   playing, which can be unsaved changes, so the plugin keeps track itself.
my $prefs = preferences('plugin.pcpequaliser');

use constant BANDS   => 10;
use constant CGI     => '/cgi-bin/xtras_alsaequal.cgi';
use constant TIMEOUT => 8;

sub initPlugin {
    my $class = shift;
    $prefs->init({ originals => {}, saved => {} });
    $class->SUPER::initPlugin(@_);

    return unless main::WEBUI;

    # A page function, not a static file: LMS serves files under html/ with a
    # week-long cache, so an updated page wouldn't show.
    Slim::Web::Pages->addPageFunction('plugins/PcpEqualiser/index.html', sub {
        my ($client, $params) = @_;
        return Slim::Web::HTTP::filltemplatefile('plugins/PcpEqualiser/index.html', $params);
    });
    Slim::Web::Pages->addPageLinks('plugins', { PLUGIN_PCPEQUALISER => 'plugins/PcpEqualiser/index.html' });
    Slim::Web::Pages->addRawFunction('plugins/PcpEqualiser/api/players', \&_apiPlayers);
    Slim::Web::Pages->addRawFunction('plugins/PcpEqualiser/api/set',     \&_apiSet);
}

sub getDisplayName { 'PLUGIN_PCPEQUALISER' }

# ── Talking to piCorePlayer ──────────────────────────────────────────────────

# Base URL of a player's pCP web interface. PCPEQ_TEST_PORT points it at a
# stand-in server when testing.
sub _pcpUrl {
    my $client = shift;
    my $ip = $client->ip or return;
    my $port = $ENV{PCPEQ_TEST_PORT} ? ":$ENV{PCPEQ_TEST_PORT}" : '';
    return "http://$ip$port" . CGI;
}

# Read the equaliser page: the current slider values, the ALSA device and
# the presets. Returns a hash with status 'ok', 'no_eq' (pCP, but the
# equaliser is switched off) or 'unreachable' (not a pCP, or no answer).
sub _readEq {
    my ($client, $cb) = @_;
    my $url = _pcpUrl($client) or return $cb->({ status => 'unreachable' });

    Slim::Networking::SimpleAsyncHTTP->new(
        sub {
            my $html = shift->content // '';
            return $cb->({ status => 'unreachable' }) unless $html =~ /piCorePlayer/;
            return $cb->({ status => 'no_eq' }) unless $html =~ /name="manual_adjust"/;

            my @values;
            for my $n (1 .. BANDS) {
                my ($v) = $html =~ /\bname="R$n"[^>]*?\bvalue="(\d+)"/s;
                return $cb->({ status => 'no_eq' }) unless defined $v;
                push @values, $v + 0;
            }
            my ($device) = $html =~ /name="CUR_EQUAL_DEVICE"\s+value="([\w-]+)"/;
            my ($version) = $html =~ /piCorePlayer (v[\d.]+)/;
            my @presets;
            while ($html =~ /<option value="([\d ]+)">\s*([^<\s]+)/g) {
                push @presets, { name => $2, values => [ map { $_ + 0 } split ' ', $1 ] };
            }
            $cb->({
                status  => 'ok',
                values  => \@values,
                device  => $device || 'equal',
                presets => \@presets,
                pcp     => $version,
            });
        },
        sub {
            my ($http, $err) = @_;
            main::INFOLOG && $log->is_info && $log->info("No pCP equaliser at $url: $err");
            $cb->({ status => 'unreachable' });
        },
        { timeout => TIMEOUT },
    )->get($url);
}

# Send values to a player: action 'Test' applies them, 'Save' also keeps
# them over a reboot - exactly the two buttons on pCP's page.
sub _writeEq {
    my ($client, $values, $device, $action, $cb) = @_;
    my $url = _pcpUrl($client) or return $cb->(0, 'no address');
    my $query = join('&', (map { "R$_=$values->[$_ - 1]" } 1 .. BANDS),
                          "CUR_EQUAL_DEVICE=$device", "ACTION=$action");

    Slim::Networking::SimpleAsyncHTTP->new(
        sub { $cb->(1) },
        sub { $log->warn("$action on " . $client->name . " failed: $_[1]"); $cb->(0, $_[1]) },
        { timeout => 20 },
    )->get("$url?$query");
}

# ── JSON routes for the page ─────────────────────────────────────────────────

sub _query {
    my $response = shift;
    my %q;
    my $raw = eval { $response->request->uri->query } // '';
    for (split /&/, $raw) {
        my ($k, $v) = split /=/, $_, 2;
        $q{uri_unescape($k)} = uri_unescape($v // '');
    }
    return \%q;
}

sub _sendJson {
    my ($httpClient, $response, $data, $code) = @_;
    $response->code($code || 200);
    $response->header('Content-Type' => 'application/json; charset=utf-8');
    $response->header('Cache-Control' => 'no-store');
    $response->content(encode_json($data));
    $httpClient->send_response($response);
    Slim::Web::HTTP::closeHTTPSocket($httpClient);
}

# All connected players, each with its equaliser state (players are asked
# in parallel).
sub _apiPlayers {
    my ($httpClient, $response) = @_;
    my @clients = sort { lc($a->name) cmp lc($b->name) } Slim::Player::Client::clients();
    return _sendJson($httpClient, $response, { players => [] }) unless @clients;

    my @players;
    my $pending = @clients;
    for my $client (@clients) {
        _readEq($client, sub {
            my $eq = shift;
            my ($original, $saved);
            if ($eq->{status} eq 'ok') {
                $original = _original($client, $eq);
                $saved = ($prefs->get('saved') || {})->{$client->id} || $original->{values};
            }
            push @players, { id => $client->id, name => $client->name, ip => $client->ip,
                             %$eq, ($original ? (original => $original, saved => $saved) : ()) };
            return if --$pending;
            @players = sort { lc($a->{name}) cmp lc($b->{name}) } @players;
            _sendJson($httpClient, $response, { players => \@players });
        });
    }
}

# The player's values from the first time the plugin saw it, recorded now
# if this is that first time.
sub _original {
    my ($client, $eq) = @_;
    my $originals = $prefs->get('originals') || {};
    unless ($originals->{$client->id}) {
        $originals->{$client->id} = {
            name   => $client->name,
            values => [ @{ $eq->{values} } ],
            device => $eq->{device},
            seen   => time,
        };
        $prefs->set('originals', $originals);
        $log->warn('Recorded original equaliser of ' . $client->name . ': ' . join(' ', @{ $eq->{values} }));
    }
    return $originals->{$client->id};
}

# set?player=<id>&values=66,66,...&action=Test|Save[&device=equal]
sub _apiSet {
    my ($httpClient, $response) = @_;
    my $q = _query($response);

    my $client = Slim::Player::Client::getClient($q->{player} // '');
    my @values = split /,/, $q->{values} // '';
    my $action = $q->{action} // '';
    my $device = $q->{device} || 'equal';

    my $bad = !$client                                   ? 'unknown player'
            : @values != BANDS                           ? 'need 10 values'
            : grep({ !/^\d+$/ || $_ > 100 } @values)     ? 'values must be 0-100'
            : $action !~ /^(?:Test|Save)$/               ? 'action must be Test or Save'
            : $device !~ /^[\w-]+$/                      ? 'bad device'
            : '';
    return _sendJson($httpClient, $response, { error => $bad }, 400) if $bad;

    _writeEq($client, \@values, $device, $action, sub {
        my ($ok, $err) = @_;
        if ($ok && $action eq 'Save') {
            my $saved = $prefs->get('saved') || {};
            $saved->{$client->id} = [ map { $_ + 0 } @values ];
            $prefs->set('saved', $saved);
        }
        _sendJson($httpClient, $response, $ok ? { ok => 1 } : { error => $err || 'failed' }, $ok ? 200 : 502);
    });
}

1;
