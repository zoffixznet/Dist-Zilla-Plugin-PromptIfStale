use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Deep;
use Path::Tiny;
use Moose::Util 'find_meta';

use lib 't/lib';
use NoNetworkHits;

my @prompts;
{
    my $meta = find_meta('Dist::Zilla::Chrome::Test');
    $meta->make_mutable;
    $meta->add_before_method_modifier(prompt_str => sub {
        my ($self, $prompt, $arg) = @_;
        push @prompts, $prompt;
    });
}

my $tzil = Builder->from_config(
    { dist_root => 't/does-not-exist' },
    {
        add_files => {
            'source/dist.ini' => simple_ini(
                [ GatherDir => ],
                [ PromptIfStale => 'via_bundle' => {
                        phase => 'build',
                        module => [ map { 'Foo' . $_ } qw(A B C J X) ],
                        check_all_prereqs => 1,
                    },
                ],
                [ Prereqs => RuntimeRequires => { map { 'Foo' . $_ => 0 } qw(J K L A Y) } ],
                [ PromptIfStale => 'direct' => {
                        phase => 'release',
                        module => [ map { 'Foo' . $_ } qw(X Y Z B K), ],
                    },
                ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
    },
);

# modules to check:
# beforebuild (build 'modules'):               A B C J X
# afterbuild  (build 'prereqs'):               J K L A Y (new: K L Y)
# release (release 'modules' and 'prereqs') :  X Y Z B K (new: Z)


my %expected_prompts = (
    before_build => [
        map { '    Foo' . $_ . ' is not installed.' } qw(A B C J X) ],
    after_build => [
        map { '    Foo' . $_ . ' is not installed.' } qw(K L Y) ],
);

my @expected_prompts = ((map {
    "Issues found:\n" . join("\n", @{$expected_prompts{$_}}, 'Continue anyway?')
} qw(before_build after_build)),
    'FooZ is not installed. Continue anyway?',
);

$tzil->chrome->set_response_for($_, 'y') foreach @expected_prompts;

$tzil->build;
$_->before_release('Foo.tar.gz') for @{ $tzil->plugins_with(-BeforeRelease) };

cmp_deeply(
    \@prompts,
    \@expected_prompts,
    'we were indeed prompted, all at once per phase, and not twice for the duplicates',
);

done_testing;
