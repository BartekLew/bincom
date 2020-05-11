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
            print $symbols "    . = $vma;\n";
            print $symbols "    $name : { *($name) }\n";
        } collect {<$sections>};
        print $symbols "}\n\n";
    });
});

my @code = ();
my %labels = ();
my $lastlab = 0;

sub newlab {
    my ($type) = @_;
    $lastlab++;
    return sprintf("${type}_%x", $lastlab);
}

sub addrlab {
    my ($addr, $rip, $type, $name) = @_;

    if($addr =~ /^[[:xdigit:]]+\s*$/) {
        if(defined($name)) {
            $labels{$addr} = $name;
        } else {
            $labels{$addr} = newlab($type) unless(defined($labels{$addr}));
        }

        return $labels{$addr};
    } elsif ($addr =~ /^*(0x[[:xdigit:]]+\(%rip\))/) {
        my $efadr = sprintf("%x", $rip + $1);
        if(defined($name)) {
            $labels{$efadr} = $name;
        } else {
            $labels{$efadr} = newlab($type) unless(defined($labels{$efadr}));
        }
        return $labels{$efadr};
    } 

    return $addr;
}

my $entry = get_entry($bin);
$labels{$entry} = "entry";
on_file("objdump -d -j .text --start-address=0x$entry '$bin' |", sub {
    my ($disasm) = @_;

    while (my $line = <$disasm>) {
        if($line =~ /^([[:xdigit:]]+) <([^@]+)@@([^->]+)>:/) {
            my ($addr, $lab) = (trim($1), $2);
            $addr =~ s/^0+//;
            $labels{$addr} = $lab;
        } elsif ($line =~ /^\s*([[:xdigit:]]+):\s+(([[:xdigit:]]{2} )+)\s+((addr32\s+)?\w+)\s*([^<#\t\n]+)?(.*$)?/) {
            my ($op, $args, $addr, $mc, $rest) = ($4, $6, trim($1), $2, $7);
            if($op =~ /^(addr32\s+)?(call|j\w+)/) {
                my $type = $2;
                my $rip = "0x$addr" + scalar(split(/ /, $mc));
                if($rest =~ /<([^>-]+)>/) {
                    $args = addrlab(trim($args), $rip, $type, $1);
                } else {
                    $args = addrlab(trim($args), $rip, $type);
                }
            }
    
            if($args =~ /%eiz/) {
                push(@code, [$addr, "_raw_", $mc, $op, $args]);
            } else {
                push(@code, [$addr, $op, $args, $mc]);
            }

            last if($op =~ /(jmp|ret)/);
        } elsif ($line =~ /^\s*([[:xdigit:]]+):\s*(([[:xdigit:]]{2} ?)+)(.*)/) {
            my ($addr, $mc, $rest) = (trim($1), $2, $3);
            push(@code, [$addr, "_raw_", $mc, $rest]);
        } 
    }
});

for my $line (@code) {
    my $addr = $line->[0];
    if(defined($labels{$addr})) {
        print "\n$labels{$addr}:\n";
    }
    print join(" / ", @$line) . "\n";
}

for my $addr (keys %labels) {
    print "$addr -> $labels{$addr}\n";
}
