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

my ($bin) = @ARGV;

open(my $sections, "objdump -h '$bin' |")
    or die "Can't objdump -h $bin";

open(my $symbols, ">", "$bin.ld")
    or die "Can't write $bin.ld.";

while(my $line = <$sections>) {
    if($line =~ /^Idx/) {last;}
}

print $symbols "SECTIONS {\n";
pairs {
    my ($x, $ind, $name, $len, $vma, $lma, $fpos, $align, @flags) =
            split /\s+/, "$_[0] $_[1]";
    $vma =~ s/^0*/0x0/;
    print $symbols "    . = $vma;\n";
    print $symbols "    $name : { *($name) }\n";
} collect {<$sections>};
print $symbols "}\n\n";

close($sections);

open(my $disasm, "objdump -d -j .text '$bin' |")
    or die "Can't objdump -d -j .text $bin.";

my @code = ();
my %labels = ();
my $lastlab = 0;

sub newlab {
    my ($type) = @_;
    $lastlab++;
    return sprintf("${type}_%x", $lastlab);
}

sub addrlab {
    my ($addr, $rip, $type) = @_;

    if($addr =~ /^[[:xdigit:]]+\s*$/) {
        $labels{$addr} = newlab($type) unless(defined($labels{$addr}));
        return $labels{$addr};
    } elsif ($addr =~ /^*(0x[[:xdigit:]]+\(%rip\))/) {
        my $efadr = $rip + $1;
        $labels{$efadr} = newlab($type) unless(defined($labels{$efadr}));
        return $labels{$efadr};
    } 

    return $addr;
}

while (my $line = <$disasm>) {
    if($line =~ /^([[:xdigit:]]+) <([^@]+)@@([^>]+)>:/) {
        my ($addr, $lab) = (trim($1), $2);
        $addr =~ s/^0+//;
        $labels{$addr} = $lab;
    } elsif ($line =~ /^\s*([[:xdigit:]]+):\s+(([[:xdigit:]]{2} )+)\s+((addr32\s+)?\w+)\s+([^<#\t\n]+)/) {
        my ($op, $args, $addr, $mc) = ($4, $6, trim($1), $2);
        if($op =~ /^(addr32\s+)?(call|j\w+)/) {
            $args = addrlab(trim($args), "0x$addr" + scalar(split(/ /, $mc)), $2);
        }

        if($args =~ /%eiz/) {
            push(@code, [$addr, "_raw_", $mc, $op, $args]);
        } else {
            push(@code, [$addr, $op, $args, $mc]);
        }
    } elsif ($line =~ /^\s*([[:xdigit:]]+):\s*(([[:xdigit:]]{2} ?)+)(.*)/) {
        my ($addr, $mc, $rest) = (trim($1), $2, $3);
        push(@code, [$addr, "_raw_", $mc, $rest]);
    } 
}

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

close($symbols);

