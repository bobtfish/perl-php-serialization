package PHP::Serialization;
use strict;
use warnings;
use Exporter ();
use Scalar::Util qw/blessed/;
use Carp qw(croak confess);
use bytes;

use vars qw/$VERSION @ISA @EXPORT_OK/;

$VERSION = '0.31';
	
@ISA = qw(Exporter);	
@EXPORT_OK = qw(unserialize serialize);

=head1 NAME

PHP::Serialization - simple flexible means of converting the output of PHP's serialize() into the equivalent Perl memory structure, and vice versa.

=head1 WARNING

B<NOTE:> Not recommended for use, this module is mostly unmaintained, and has
several severe known bugs. See the following for more information:

=over

=item L<http://rt.cpan.org/Ticket/Display.html?id=21218>

=item L<http://rt.cpan.org/Ticket/Display.html?id=24441>

=item L<http://rt.cpan.org/Ticket/Display.html?id=42029>

=item L<http://rt.cpan.org/Ticket/Display.html?id=44700>

=back

Patches to fix any of these bugs are more than welcome!

=head1 SYNOPSIS

	use PHP::Serialization qw(serialize unserialize);
	my $encoded = serialize({ a => 1, b => 2});
	my $hashref = unserialize($encoded);

=cut


=head1 DESCRIPTION

Provides a simple, quick means of serializing perl memory structures (including object data!) into a format that PHP can deserialize() and access, and vice versa. 

NOTE: Converts PHP arrays into Perl Arrays when the PHP array used exclusively numeric indexes, and into Perl Hashes then the PHP array did not.

=cut

sub new {
    my ($class) = shift;
	my $self = bless {}, blessed($class) ? blessed($class) : $class;
	return $self;
}

=head1 FUNCTIONS

Exportable functions..

=cut

=head2 serialize($var)

Serializes the memory structure pointed to by $var, and returns a scalar value of encoded data. 

NOTE: Will recursively encode objects, hashes, arrays, etc. 

SEE ALSO: ->encode()

=cut

sub serialize {
	return __PACKAGE__->new->encode(@_);
}

=head2 unserialize($encoded,[optional CLASS])

Deserializes the encoded data in $encoded, and returns a value (be it a hashref, arrayref, scalar, etc) 
representing the data structure serialized in $encoded_string.

If the optional CLASS is specified, any objects are blessed into CLASS::$serialized_class. Otherwise, O
bjects are blessed into PHP::Serialization::Object::$serialized_class. (which has no methods)

SEE ALSO: ->decode()

=cut

sub unserialize {
	return __PACKAGE__->new->decode(@_);
}

=head1 METHODS

Functionality available if using the object interface..

=cut

=head2 decode($encoded_string,[optional CLASS])

Deserializes the encoded data in $encoded, and returns a value (be it a hashref, arrayref, scalar, etc) 
representing the data structure serialized in $encoded_string.

If the optional CLASS is specified, any objects are blessed into CLASS::$serialized_class. Otherwise, 
Objects are blessed into PHP::Serialization::Object::$serialized_class. (which has no methods)

SEE ALSO: unserialize()

=cut

sub decode {
	my ($self, $string, $class) = @_;

	my $cursor = 0;
	$self->{string} = \$string;
	$self->{cursor} = \$cursor;
	$self->{strlen} = length($string);

	if ( defined $class ) {
		$self->{class} = $class;
	} 
	else {
		$self->{class} = 'PHP::Serialization::Object';
	}	

	# Ok, start parsing...
	my @values = $self->_parse();

	# Ok, we SHOULD only have one value.. 
	if ( $#values == -1 ) {
		# Oops, none...
		return;
	} 
	elsif ( $#values == 0 ) {
		# Ok, return our one value..
		return $values[0];
	} 
	else {
		# Ok, return a reference to the list.
		return \@values;
	}

} # End of decode sub.

my %type_table = (
	O => 'object',
	s => 'scalar',
	a => 'array',
	i => 'integer',
	d => 'float',
	b => 'boolean',
	N => 'undef',
);


sub _parse {
	my ($self) = @_;
	my $cursor = $self->{cursor};
	my $string = $self->{string};
	my $strlen = $self->{strlen};
	confess("No cursor") unless $cursor;
	confess("No string") unless $string;
	confess("No strlen") unless $strlen;
	my @elems;	
	while ( $$cursor < $strlen ) {
		# Ok, decode the type...
		my $type = $self->_readchar();
		# Ok, see if 'type' is a start/end brace...
		next if ( $type eq '{' );
		last if ( $type eq '}' );

		if ( ! exists $type_table{$type} ) {
			confess "Unknown type '$type'! at $$cursor";
		}
		$self->_skipchar; # Toss the seperator
		$type = $type_table{$type};
	
		# Ok, do per type processing..
		if ( $type eq 'object' ) {
			# Ok, get our name count...
			my $namelen = $self->_readnum();
			$self->_skipchar;

			# Ok, get our object name...
			$self->_skipchar;
			my $name = $self->_readstr($namelen);
			$self->_skipchar;

			# Ok, our sub elements...
			$self->_skipchar;
			my $elemcount = $self->_readnum();
			$self->_skipchar;

			my %value = $self->_parse();
			push(@elems, bless(\%value, $self->{class} . '::' . $name));
		} elsif ( $type eq 'array' ) {
			# Ok, our sub elements...
			$self->_skipchar;
			my $elemcount = $self->_readnum();
			$self->_skipchar;

			my @values = $self->_parse();
			# If every other key is not numeric, map to a hash..
			my $subtype = 'array';
			my @newlist;
			foreach ( 0..$#values ) {
				if ( ($_ % 2) ) { 
					push(@newlist, $values[$_]);
					next; 
				}
				if ( $values[$_] !~ /^\d+$/ ) {
					$subtype = 'hash';
					last;
				}
			}
			if ( $subtype eq 'array' ) {
				# Ok, remap...
				push(@elems, \@newlist);
			} else {
				# Ok, force into hash..
				my %hash = @values;
				push(@elems, \%hash);
			}
		} 
		elsif ( $type eq 'scalar' ) {
			# Ok, get our string size count...
			my $strlen = $self->_readnum;
			$self->_skipchar;

			$self->_skipchar;
			my $string = $self->_readstr($strlen);
			$self->_skipchar;
			$self->_skipchar;
		
			push(@elems,$string);	
		} 
		elsif ( $type eq 'integer' || $type eq 'float' ) {
			# Ok, read the value..
			my $val = $self->_readnum;
			if ( $type eq 'integer' ) { $val = int($val); }
			$self->_skipchar;
			push(@elems, $val);
		} 
		elsif ( $type eq 'boolean' ) {
			# Ok, read our boolen value..
			my $bool = $self->_readchar;
			$self->_skipchar;
            if ($bool eq '0') {
                $bool = undef;
            }
			push(@elems, $bool);
		} 
		elsif ( $type eq 'undef' ) {
			# Ok, undef value..
			push(@elems, undef);
		} 
		else {
			confess "Unknown element type '$type' found! (cursor $$cursor)";
		}
	} # End of while.

	# Ok, return our elements list...
	return @elems;
	
} # End of decode.

sub _readstr {
	my ($self, $length) = @_;
	my $string = $self->{string};
	my $cursor = $self->{cursor};
	my $str = substr($$string, $$cursor, $length);
	$$cursor += $length;

	return $str;
}

sub _readchar {
	my ($self) = @_;
	return $self->_readstr(1);
}

sub _readnum {
	# Reads in a character at a time until we run out of numbers to read...
	my ($self) = @_;
	my $cursor = $self->{cursor};

	my $string;
	while ( 1 ) {
		my $char = $self->_readchar;
		if ( $char !~ /^[\d\.-]+$/ ) {
			$$cursor--;
			last;
		}
		$string .= $char;
	} # End of while.

	return $string;
} # End of readnum

sub _skipchar {
	my $self = shift;
	${$$self{cursor}}++;
} # Move our cursor one bytes ahead...


=head2 encode($reference)

Serializes the memory structure pointed to by $var, and returns a scalar value of encoded data. 

NOTE: Will recursively encode objects, hashes, arrays, etc. 

SEE ALSO: serialize()

=cut

sub encode {
	my ($self, $val) = @_;

	if ( ! defined $val ) {
		return $self->_encode('null', $val);
	}
	elsif ( blessed $val ) {
	    return $self->_encode('obj', $val);
	}
	elsif ( ! ref($val) ) {
		if ( $val =~ /^-?\d{1,10}$/ && abs($val) < 2**31 ) {
			return $self->_encode('int', $val);
		} 
		elsif ( $val =~ /^-?\d+\.\d*$/ ) {
			return $self->_encode('float', $val);
		} 
		else {
			return $self->_encode('string', $val);
		}
	} 
	else {
		my $type = ref($val);
		if ($type eq 'HASH' || $type eq 'ARRAY' ) {
			return $self->_encode('array', $val);
		} 
		else {
			confess "I can't serialize data of type '$type'!";
		}
	}
}

sub _encode {
	my ($self, $type, $val) = @_;

	my $buffer = '';
	if ( $type eq 'null' ) {
		$buffer .= 'N;';
	} 
	elsif ( $type eq 'int' ) {
		$buffer .= sprintf('i:%d;', $val);
	} 
	elsif ( $type eq 'float' ) {
		$buffer .= sprintf('d:%s;', $val);
	} 
	elsif ( $type eq 'string' ) {
		$buffer .= sprintf('s:%d:"%s";', length($val), $val);
	} 
	elsif ( $type eq 'array' ) {
		if ( ref($val) eq 'ARRAY' ) {
			$buffer .= sprintf('a:%d:',($#{$val}+1)) . '{';
			map { # Ewww
			    $buffer .= $self->encode($_); 
			    $buffer .= $self->encode($$val[$_]); 
			} 0..$#{$val};
			$buffer .= '}';
		} 
		else {
			$buffer .= sprintf('a:%d:',scalar(keys(%{$val}))) . '{';
			foreach ( %{$val} ) { 
			    $buffer .= $self->encode($_); 
			}
			$buffer .= '}';	
		}
	} 
	elsif ( $type eq 'obj' ) {
		my $class = ref($val);
		$class =~ /(\w+)$/;
		my $subclass = $1;
		$buffer .= sprintf('O:%d:"%s":%d:', length($subclass), $subclass, scalar(keys %{$val})) . '{';
		foreach ( %{$val} ) { 
		    $buffer .= $self->encode($_); 
		}
		$buffer .= '}';
	} 
	else {
		confess "Unknown encode type!";
	}	
	return $buffer;	

}

=head1 TODO

Make faster! (and more efficent?)

=head1 AUTHOR INFORMATION

Copyright (c) 2003 Jesse Brown <jbrown@cpan.org>. All rights reserved. This program is free software; 
you can redistribute it and/or modify it under the same terms as Perl itself.

Various patches contributed by assorted authors on rt.cpan.org (as detailed in Changes file).

Currently maintained by Tomas Doran <bobtfish@bobtfish.net>.

=cut

package PHP::Serialization::Object;

1;
