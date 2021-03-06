#!/usr/bin/perl

use strict;

sub pairs (&@) {
    my ($block, @elements) = @_;
    for(my $i = 0; $i < @elements/2; $i++) {
        &$block($elements[2*$i], $elements[2*$i+1]);
    }
}

sub collect(&) {
    my $block = $_[0];
    my @coll = ();
    while(my $x = $block->()) {
        push(@coll, $x);
    }
    return @coll;
}

sub trim {
    my ($instr) = @_;
    $instr =~ s/(^\s+|\s+$)//;
    return $instr;
}

sub on_file {
    my ($file, $sub) = @_;
    open(my $file, $file) or die "Can't open '$file'.";

    my $result = &$sub($file);

    close($file);
    return $result;
}

sub get_entry {
    my ($tgt) = @_;
    return on_file("readelf -h '$tgt' |", sub {
        my ($in) = @_;
        while (my $l = <$in>) {
            if($l =~ /Entry point address:\s*0x([[:xdigit:]]+)/) {
                return $1;
            }
        }
    });
}

my ($bin) = @ARGV;
my %sections = ();

on_file("objdump -h '$bin' |", sub {
    my ($sections) = @_;

    while(my $line = <$sections>) {
        if($line =~ /^Idx/) {last;}
    }

    on_file(">$bin.ld", sub {
        my ($symbols) = @_;

        print $symbols "SECTIONS {\n";
        pairs {
            my ($x, $ind, $name, $len, $vma, $lma, $fpos, $align, @flags) =
                    split /\s+/, "$_[0] $_[1]";
            $vma =~ s/^0*/0x0/;
            $len =~ s/^0*/0x0/;

            $sections{$name} = [$vma,sprintf("0x%x", $vma+$len),$fpos];

            print $symbols "    . = $vma;\n";
            print $symbols "    $name : { *($name) }\n";
        } collect {<$sections>};
        print $symbols "}\n\n";
    });
});

sub sectof {
    my ($addr) = @_;
    for my $sect (keys %sections) {
        my @range = @{$sections{$sect}};
        if("0x$addr" >= $range[0] && "0x$addr" < $range[1]) {
            $sect =~ s/^\.//;
            return $sect;
        }
    }

    return "unknown";
}

sub lines {
    my ($fh, $interp, $stopcond) = @_;
    my @result = ();

    while(my $line = <$fh>) {
        my $ans = &$interp($line);
        if (defined($ans)) {
            push(@result, $ans);
        }

        last if(defined($ans) && &$stopcond($ans));
    }

    return \@result;
}

sub disassemble {
    my ($file, $entry, $label) = @_;

    my %labels = ($entry => $label);
    my $lastlab = 0;
    
    sub newlab {
        my ($sect, $type) = @_;
        $lastlab++;
        return sprintf("${sect}_${type}_%x", $lastlab);
    }
    
    sub addrlab {
        my ($addr, $rip, $type, $name, $labels) = @_;
    
        if($addr =~ /^[[:xdigit:]]+\s*$/) {
            if(defined($name)) {
                $labels->{$addr} = $name;
            } else {
                $labels->{$addr} = newlab(sectof($addr), $type) unless(defined($labels->{$addr}));
            }
            return $labels->{$addr};
        } elsif ($addr =~ /^*(-?0x[[:xdigit:]]+\(%rip\))/) {
            my $efadr = sprintf("%x", $rip + $1);
            if(defined($name)) {
                $labels->{$efadr} = $name;
            } else {
                $labels->{$efadr} = newlab(sectof($efadr), $type) unless(defined($labels->{$efadr}));
            }

            return $labels->{$efadr};
        } 
    
        return $addr;
    }

    sub detect_label {
        my ($rest) = @_;

        if($rest =~ /<([^>\-+]+)>/) {
            $1 =~ /^_*([^@]+)/;
            return $1;
        }

        return undef;
    }

    sub adjust_args {
        my ($op, $args, $addr, $mc, $rest, $labels) = @_;

        if($op =~ /^(addr32\s+)?(call|j\w+)/) {
            my $type = $2;
            my $rip = "0x$addr" + scalar(split(/ /, $mc));

            $args = addrlab(trim($args), $rip, $type, detect_label($rest), $labels);
        } elsif ($op =~ /^(lea|mov)/) {
            my $rip = "0x$addr" + scalar(split(/ /, $mc));
            my @opnds = split(",", $args);
            for(my $i = 0; $i<2; $i++) {
                $opnds[$i] = addrlab($opnds[$i], $rip, $1, detect_label($rest),$labels);
            }
            $args = join(",", @opnds);
        }

        return $args;
    }

    my $code = on_file("objdump -d -j .text --start-address=0x$entry '$file' |", sub {
        my ($disasm) = @_;
    
        return lines($disasm, sub {
            my ($line) = @_;
            if($line =~ /^([[:xdigit:]]+) <([^@]+)@@([^-+>]+)>:/) {
                my ($addr, $lab) = (trim($1), $2);
                $addr =~ s/^0+//;
                $labels{$addr} = $lab;
            } elsif ($line =~ /^\s*([[:xdigit:]]+):\s+(([[:xdigit:]]{2} )+)\s+((addr32\s+)?\w+)\s*([^<#\t\n]+)?(.*$)?/) {
                my ($op, $args, $addr, $mc, $rest) = ($4, $6, trim($1), $2, $7);
                $args = adjust_args($op, $args, $addr, $mc, $rest, \%labels);
        
                if($args =~ /%eiz/) {
                    return [$addr, "_raw_", $mc, $op, $args];
                } else {
                    return [$addr, $op, $args, $mc];
                }
            } elsif ($line =~ /^\s*([[:xdigit:]]+):\s*(([[:xdigit:]]{2} ?)+)(.*)/) {
                my ($addr, $mc, $rest) = (trim($1), $2, $3);
                return [$addr, "_raw_", $mc, $rest];
            } 
            return undef;
        }, sub { $_[0]->[1] =~ /(ret|jmp)/ });
    });

    return (\%labels, $code);
}

sub peek {
    print "$_[0]\n";
    return $_[0];
}

my $totunus = 0;
sub code_block {
    my ($code) = @_;

    my @base = sort {hex("0x$a->[0]") <=> hex("0x$b->[0]");} @$code;
    my $last = shift @base;
    my @acc = ($last);

    for my $next (@base) {
        next if ($next->[0] eq $last->[0]);
        my $lastaddr = "0x$last->[0]";
        my $lastmc;
        if($last->[1] eq "_raw_") {
            $lastmc = $last->[2];
        } else {
            $lastmc = $last->[3];
        }
        my $rip = sprintf("%x", $lastaddr + scalar(split /\s+/, $lastmc));
        if("0x$rip" != "0x$next->[0]") {
            push(@acc, ["\nunused", $rip, $next->[0], "0x$next->[0]" - "0x$rip"]);
            $totunus += "0x$next->[0]" - "0x$rip";
        } 

        push(@acc, $next);
        $last = $next;
    }

    return \@acc;
}

sub disassemble_function {
    my ($binary, $entry, $label) = @_;

    my @ignore_labels = ();
    my ($labels, $code) = disassemble($binary, $entry, $label); 
    my @more_labels = keys %$labels;

    while (scalar(@more_labels) > 0) {
        my $lab = shift @more_labels;

        print STDERR (scalar(@more_labels) . "/" . scalar(@ignore_labels) . "\r");
        #print ("disass fun $lab($labels->{$lab}):\n  more: " . join(",", @more_labels)
        #            . "\n  ignore: " . join(",", @ignore_labels) . "\n");

        if(sectof($lab) eq "text" && !(grep {$_ eq $lab} @ignore_labels)) {
            my ($nlabs, $ncode) = disassemble($binary, $lab, $labels->{$lab});

            push(@$code, @$ncode);
            %$labels = (%$labels, %$nlabs);
            push(@ignore_labels, $lab);
            push(@more_labels, keys %$nlabs);
        }
    }

    return ($labels, code_block($code));
}

my ($labels, $code) = disassemble_function($bin, get_entry($bin), "entry");

for my $line (@$code) {
    my $addr = $line->[0];
    if(defined($labels->{$addr})) {
        print "\n$labels->{$addr}:\n";
    }
    print join(" / ", @$line) . "\n";
}

print "\n";

for my $addr (keys %$labels) {
    print "$addr -> $labels->{$addr}\n";
}

print "$totunus\n";
