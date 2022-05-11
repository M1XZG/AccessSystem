package AccessSystem::TelegramBot;

use feature 'signatures';

use Mojo::Base 'Telegram::Bot::Brain';
use Telegram::Bot::Object::InlineKeyboardMarkup;
use Telegram::Bot::Object::InlineKeyboardButton;
use Config::General;
use LWP::Simple;
use LWP::UserAgent;
use lib "$ENV{BOT_HOME}/lib";
use AccessSystem::Schema;

has _token => undef;
has token => sub {
    my ($self) = @_;
    if (!$self->_token) {
        my %conf = Config::General->new("$ENV{BOT_HOME}/keys.conf")->getall();
        $self->_token($conf{'Telegram::Bot'}{'api'});
    };
    return $self->_token();
};

has _db => undef;
has 'db' => sub {
    my ($self) = @_;
    if(!$self->_db) {
        my $db_info = $self->mainconfig->{'Model::AccessDB'}{connect_info};
        $self->_db(AccessSystem::Schema->connect($db_info->{dsn}, $db_info->{user}, $db_info->{password}));
    }
    return $self->_db();
};

has _mainconfig => undef;
has 'mainconfig' => sub ($self) {
    if (!$self->_mainconfig) {
        $self->_mainconfig(Config::General->new("$ENV{BOT_HOME}/accesssystem_api.conf")->getall());
    }

    if (wantarray) {
        return %{$self->_mainconfig};
    } else {
        return $self->_mainconfig;
    }
};

has waiting_on_response => sub { return {}; };

sub init {
    my $self = shift;
    $self->add_listener(\&read_message);
}

sub member ($self, $message) {
    return $self->db->resultset('Person')->find({ telegram_chatid => $message->from->id });
}

=head1 authorize
   
   return unless $self->authorize($message);

Check if the sender of the C<$message> is a currently valid member.

   return unless $self->authorize($message, 'invalid_ok');

Check if we know who this is, but allow the command to continue if they aren't paid up.

=cut

sub authorize ($self, $message, @tags) {
    my $member = $self->member($message);
    my %tags = map {$_ => 1} @tags;

    if (!$member) {
        $message->reply("I don't know who you are.  Please use /identify and then try again.");
        return undef;
    }

    return 1 if $tags{invalid_ok};

    if (!$member->is_valid) {
        $message->reply("I know who you are, but your membership has expired, as of ".$member->valid_until."."
        . "  If you need payment details again, please use the /bankinfo command.  "
        );
        return undef;
    }

    return 1;
}

sub read_message {
    my ($self, $message) = @_;
    my %methods = (
        memberstats   => qr{^/memberstats},
        identify      => qr{^/identify},
        doorcode      => qr{^/doorcode},
        tools         => qr{^/tools$},
        add_tool      => qr{^/add_tool},
        induct_member => qr{^/induct\s},
        inducted_on   => qr{^/inducted_on\s},
        inductions    => qr{^/inductions\s},
        help          => qr{^/(help|start)},
        );

    print STDERR ref $message;
    if (ref $message eq 'Telegram::Bot::Object::Message') {
        foreach my $method (keys %methods) {
            if ($message->text =~ /$methods{$method}/) {
                return $self->$method($message);
            }
        }
    } elsif (ref $message eq 'Telegram::Bot::Object::CallbackQuery') {
        print STDERR "Calling resolve\n";
        return $self->resolve_callback($message);
    }
    if ($message->text =~ m{^/}) {
        $message->reply(qq<I don't know that command, sorry.>);
    }
}

sub bankinfo {
    my ($self, $message) = @_;

    return unless $self->authorize($message, 'invalid_ok');

    my $member = $self->member($message);

    my $dues = sprintf('%.2f', $member->dues / 100);
    my $bank_ref = $member->bank_ref;

    my $text = <<"END";
Monthly fee: $dues/month</li>
To: Swindon Makerspace
Bank: Barclays
Sort Code: 20-84-58
Account: 83789160
Ref: $bank_ref
END

    $message->reply($text);
}

sub memberstats {
    my ($self, $message) = @_;
    
    if($message->text =~ m{^/memberstats}) {
        my $data = $self->db->resultset('Person')->membership_stats;
        my $msg_text = "
Current members: " . ($data->{valid_members}{count} || 0) . " - (" . join(', ', map { "$_: " . ($data->{valid_members}{$_} || 0) } (qw/full concession otherspace adult child/)) . "),
Ex members: " . ($data->{ex_members}{count} || 0) . " - (" . join(', ', map { "$_: " . ($data->{ex_members}{$_} || 0) } (qw/full concession otherspace/)) . "),
Overdue members: " . ($data->{overdue_members}{count} || 0) ." - (" . join(', ', map { "$_: " . ($data->{overdue_members}{$_} || 0) } (qw/full concession otherspace/)) . "),
Left this month: " . ($data->{recent_expired}{count} || 0) ." - (" . join(', ', map { "$_: " . ($data->{recent_expired}{$_} || 0) } (qw/full concession otherspace/)) . ")";

        $message->reply($msg_text);

        return;
    }
}

sub identify {
    my ($self, $message) = @_;
    
    if($message->text =~ m{^/identify}) {
        if($message->text =~ m{^/identify ([ -~]+\@[ -~]+)$}) {
            my $email = $1;
            # print STDERR "Email: $email\n";
            my $members = $self->db->resultset('Person')->search_rs({
                '-and' => [
                    end_date => undef,
                    \ ['LOWER(email) = ?', lc($email)],
                   ]});
            if($members->count == 1) {
                my $url = 'http://localhost:3000/confirm_telegram?chatid=' . $message->from->id . '&email=' . lc($email) . '&username=' . $message->from->username;
                # print STDERR "Calling: $url\n";
                my $ua = LWP::UserAgent->new();
                my $resp = $ua->get($url);
                if (!$resp->is_success) {
                    print STDERR "Failed: ", $resp->status_line, " ", $resp->content, "\n";

                }
                # my $member = $members->first;
                # if(!$member->telegram_chatid) {
                #     $member->update({ telegram_chatid => $message->from->id, telegram_username => $message->from->username });
                #     $message->reply('Set your telegram chatid to ' . $message->from->id);
                # } else {
                #     $message->reply('Your telegram chatid is already set! Ask a director to unset it');
                # }
                $message->reply("You should have an email to confirm your membership/telegram mashup");
            } else {
                $message->reply("I can't find a member with that email address, try again or check https://inside.swindon-makerspace.org/profile");
            }
        } else {
            $message->reply("That didn't look like an email address, try again?");
        }

       return;
    }
}

sub doorcode {
    my ($self, $message) = @_;
    
    return unless $self->authorize($message);

    my $doorcode = $self->mainconfig->{code_a};

    $message->reply("Use $doorcode on the keypad by either external door of BSS House to get in at night.");
}

=head2 tools

Output a list of tool names.

=cut

sub tools ($self, $message) {
    my $tools = $self->db->resultset('Tool');
    $tools->result_class('DBIx::Class::ResultClass::HashRefInflator');

    my $tool_str = join("\n", map { $_->{name} . ($_->{requires_induction} ? ' (induction)' : '') } ($tools->all));
    $message->reply($tool_str);
}

=head2 add_tool

Add a new makerspace tool (especially if it requires induction)

=cut

sub add_tool ($self, $message) {
    print "Add tool\n";
    if ($message->text =~ m{/add_tool ([\w\d ]+)$}) {
        my $name = $1;
        print "Name: $name\n";
        # Each user can only have one response they're waiting on at a time?
        $self->waiting_on_response()->{$message->from->id} = {
            'action' => 'add_tool',
                'name' => $name
        };
        $message->_brain->sendMessage({
            chat_id => $message->chat->id,
            text => "Adding $1 ... \nDoes it need induction?",
            reply_markup => Telegram::Bot::Object::InlineKeyboardMarkup->new({
                inline_keyboard => [[
                    Telegram::Bot::Object::InlineKeyboardButton->new({
                        text => 'Yes',
                        callback_data => "add_tool|$name|Yes",
                    }),
                    Telegram::Bot::Object::InlineKeyboardButton->new({
                        text => 'No',
                        callback_data => "add_tool|$name|No",
                    }),
                ]]
            })
        });
    }
}

=head2 induct_member

Create an "allowed" link between a member and a tool

=cut

sub induct_member ($self, $message) {
    ## User calling this should be authorised with Telegram, paid up
    ## AND be an admin on the tool
    #                        /induct James Mastros on Point of Sale
    if ($message->text =~ m{^/induct\s([\w\s]+)\son\s([\w\d\s]+)$}) {
        my ($name, $tool_name) = ($1, $2);
        my $member = $self->member($message);
        my $tool = $self->db->resultset('Tool')->find({name => $tool_name});
        if (!$tool) {
            return $message->reply("I can't find a tool named $tool_name");
        }
        if ($tool && $member) {
            if (!$member->allowed->find({ tool_id => $tool->id, is_admin => 1})) {
                return $message->reply("You're not allowed to induct people on the $tool_name");
            }
            my $person = $self->db->resultset('Person')->find({name => $name});
            if (!$person) {
                return $message->reply("I can't find a person named $name");
            }
            if (!$person->is_valid) {
                return $message->reply("I found $name but they aren't a paid-up member");
            }
            $person->create_related('allowed', { tool_id => $tool->id });
            return $message->reply("Ok, inducted $name on $tool_name");
        }   
    }
    return $message->reply("Try /induct <person name> on <tool name> or /help");
}

=head inductees

Who is inducted on this thing?

=cut

sub inducted_on ($self, $message) {
    ## Calling user should be authorised (and paid up?)
    if ($message->text =~ m{^/inducted_on\s([\w\s\d]+)$}) {
        my $tool_name = $1;
        my $tool = $self->db->resultset('Tool')->find(
            {
                name => $tool_name,
            },
            {
                prefetch=> {'allowed_people' => 'person'},
            });
        if (!$tool) {
            return $message->reply("I can't find a tool named $tool_name");
        }
        my $str = join("\n", map { $_->person->name } ($tool->allowed_people));
        if (!$str) {
            $str = 'Nobody !?';
        }
        return $message->reply("Inducted on $tool_name:\n$str");
    }
}

=head2 inductions

What can this person use?

=cut

sub inductions ($self, $message) {
    ## Calling user should be authorised (and paid up?)
    if ($message->text =~ m{^/inductions\s([\w\s]+)$}) {
        my $name = $1;
        my $person = $self->db->resultset('Person')->find(
            { name => $name },
            { prefetch => {'allowed' => 'tool'}});
        if (!$person) {
            return $message->reply("I can't find a person named $name");
        }

        my $str = join("\n", map { $_->tool->name } ($person->allowed));
        if (!$str) {
            $str = 'Nothing !?';
        }
        return $message->reply("Inductions for $name:\n$str");        
    }
}
    

sub resolve_callback ($self, $callback) {
    my $waiting = $self->waiting_on_response->{$callback->from->id};
    if (!$waiting) {
        $callback->_brain->sendMessage({'chat_id' => $callback->message->chat->id, text => 'Confusion in the bot-brain, what are you responding to?'});
        return $callback->answer('Arghhh');
    }
    my @args = split(/\|/, $callback->data);
    if ($waiting->{action} eq $args[0] && $waiting->{name} eq $args[1]) {
        delete $self->waiting_on_response->{$callback->from->id};
        my $tool = $self->db->resultset('Tool')->update_or_create({
            name => $args[1],
            requires_induction => $args[2] eq 'Yes' ? 1 : 0,
            # team?
        });
        if (!$tool) {
            return $callback->answer('Failed');
        }
        return $callback->answer('Created');
    }
    return $callback->answer('Confused!');
}


sub help {
    my ($self, $message) = @_;
    if ($message->text =~ m!^/(help|start)!) {
        $message->reply("I know /identify <your email address>, /memberstats, /doorcode, /tools, /add_tool, /induct, /inducted_on, /inductions");
    }
}
1;
