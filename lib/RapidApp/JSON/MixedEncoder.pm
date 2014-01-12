package RapidApp::JSON::MixedEncoder;

use strict;
use warnings;
use Scalar::Util 'blessed';
use Data::Dumper;
use base 'JSON::PP';

our @EXPORT = qw{encode_json decode_json encode_json_utf8 decode_json_utf8};

# ---
# These are values that we might encounter as ScalarRefs and how to
# translate them into safe values for the JSON encoder. There are 
# only a few cases that I am aware of so far, but as new values are
# identified this is where they should be put.
# (Note: \0 and \1 are already handled and expected by the JSON encoder)
# (Note: vals are lc before being tested, so \'NULL' is already seen as \'null')
our %SCALARREF_VALUE_MAP = (
  
  # This has been seen in 'default_value' in sources generated by 
  # Schema::Loader from SQLite databases
  "null" => undef,
  
  # This has also been seen in 'default_value' generated by S::L. Also
  # setting this to undef because I'm not aware of any other better value
  "current_timestamp" => undef,
  
  # Add additional cases here ...
);
# ---


# copied from JSON::PP
my $JSON; # cache
sub encode_json ($) { # encode
	($JSON ||= __PACKAGE__->new)->encode($_[0]);
}
sub decode_json ($) { # decode
	($JSON ||= __PACKAGE__->new)->decode($_[0]);
}

my $JSONUtf8; # cache
sub encode_json_utf8 ($) { # encode
	($JSONUtf8 ||= __PACKAGE__->new->utf8)->encode($_[0]);
}
sub decode_json_utf8 ($) { # decode
	($JSONUtf8 ||= __PACKAGE__->new->utf8)->decode($_[0]);
}


sub new {
	return bless JSON::PP->new->allow_blessed->convert_blessed->allow_nonref, __PACKAGE__;
}


# We need to do this so that JSON won't quote the output of our
# TO_JSON method and will allow us to return invalid JSON...
# In this case, we're actually using the JSON lib to generate
# JavaScript (with functions), not JSON. We're also handling
# some special ScalarRef values to prevent JSON exceptions
sub object_to_json {
	my ($self, $obj)= @_;
  
  if(ref($obj) eq 'SCALAR') {
    my $val = $$obj;
    # By design \0 and \1 are expected and will be handled as true/false. But,
    # we don't expect to see any other ScalarRef values normally. But we'll
    # handle them on a case-by-case basis below:
    if ("$val" ne "0" and "$val" ne "1") {
      if(exists $SCALARREF_VALUE_MAP{lc($val)}) {
        $obj = $SCALARREF_VALUE_MAP{lc($val)};
      }
      else {
        # This is a ScalarRef value that we don't know how to handle. 
        # Default it to undef but throw a warning
        $obj = undef;
        warn join("\n",
          "\n   RapidApp::JSON::MixedEncoder: encounterd unknown ScalarRef",
          "   value '$val' - will be encoded as 'null' in JSON data.",
          "   This is a BUG. Please report this message to RapidApp developers\n"
        );
      }
    }
  }
  elsif (blessed($obj)) {
    # This handles special objects which implement a TO_JSON_RAW method, 
    # like RapidApp::JSONFunc which will return a raw function (JavaScript,
    # *not* nomral JSON)
    my $method = $obj->can('TO_JSON_RAW');
    return $method->($obj) if defined $method;
  }
  
  return $self->next::method($obj);
}

1;