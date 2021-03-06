#!/usr/bin/perl

# Copyright 2000-2002 Katipo Communications
#
# Copyright 2011 LibLime, a Division of PTFS, Inc.
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# Koha; if not, write to the Free Software Foundation, Inc., 59 Temple Place,
# Suite 330, Boston, MA  02111-1307 USA


=head1 pay.pl

 written 11/1/2000 by chris@katipo.oc.nz
 part of the koha library system, script to facilitate paying off fines

=cut

use strict;
use warnings;
use C4::Context;
use C4::Auth;
use C4::Output;
use CGI;
use C4::Members;
use C4::Accounts;
use C4::Stats;
use C4::Koha;
use C4::Overdues;
use C4::Branch; # GetBranches
use C4::Dates;
use C4::Items qw( ModItem );

my $input = new CGI;

my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name   => 'members/pay.tmpl',
        query           => $input,
        type            => 'intranet',
        authnotrequired => 0,
        flagsrequired   => { borrowers => '*', updatecharges => '*' },
        debug           => 1,
    }
);

my @nam = $input->param;
my $borrowernumber = $input->param('borrowernumber');
if ( !$borrowernumber  ) {
    $borrowernumber = $input->param('borrowernumber0');
}

# get borrower details
our $data = GetMember( $borrowernumber,'borrowernumber' );
my $user = $input->remote_user;
$user ||= q{};

# get account details
my $branches = GetBranches();
my $branch   = GetBranch( $input, $branches );

my $co_wr = $input->param('confirm_writeoff');
my $paycollect = $input->param('paycollect');
if ($paycollect) {
    print $input->redirect("/cgi-bin/koha/members/paycollect.pl?borrowernumber=$borrowernumber" );
}
my $wo_all = $input->param('woall'); # writeoff all fines
if ($wo_all) {
    writeoff_all();
} elsif ($co_wr) {
    my $accountno = $input->param('accountno');
    my $itemno = $input->param('itemnumber');
    my $account_type =  $input->param('accounttype');
    my $amount = $input->param('amount');
    writeoff($borrowernumber, $accountno, $itemno, $account_type, $amount);
}

my @names = $input->param;
my %inp;
my $check = 0;

## Create a structure
for ( my $i = 0 ; $i < @names ; $i++ ) {
    my $temp = $input->param( $names[$i] );
    if ( $temp eq 'yes' ) {

# FIXME : using array +4, +5, +6 is dirty. Should use arrays for each accountline
        my $itemnumber     = $input->param( $names[ $i + 1 ] );
        my $accounttype    = $input->param( $names[ $i + 2 ] );
        my $amount         = $input->param( $names[ $i + 4 ] );
        my $borrowernumber = $input->param( $names[ $i + 5 ] );
        my $accountno      = $input->param( $names[ $i + 6 ] );
        makepayment( $borrowernumber, $accountno, $amount, $user, $branch );

        if ( $accounttype eq 'L' && $itemnumber ) {
            my $bor = "$data->{'firstname'} $data->{'surname'} $data->{'cardnumber'}";
            ModItem( { paidfor =>  "Paid for by $bor " . C4::Dates->today() }, undef, $itemnumber );
        }
        
        $check = 2;
    }
}

for ( @names ) {
    if (/^pay_indiv_(\d+)$/) {
        my $line_no = $1;
        redirect_to_paycollect('pay_individual', $line_no);
    }
    if (/^wo_indiv_(\d+)$/) {
        my $line_no = $1;
        redirect_to_paycollect('writeoff_individual', $line_no);
    }
}

if ( $check == 0 ) {  # fetch and display accounts
    add_accounts_to_template($borrowernumber);

    output_html_with_http_headers $input, $cookie, $template->output;

}else {

    my %inp;
    my @name = $input->param;
    for my $name (@name) {
        my $test = $input->param( $name );
        if ($test eq 'wo' ) {
            my $temp = $name;
            $temp=~s/payfine//;
            $inp{ $name } = $temp;
        }
    }

    while ( my ( $key, $value ) = each %inp ) {

        my $accounttype    = $input->param("accounttype$value");
        my $borrowernumber = $input->param("borrowernumber$value");
        my $itemno         = $input->param("itemnumber$value");
        my $amount         = $input->param("amount$value");
        my $accountno      = $input->param("accountno$value");
        writeoff( $borrowernumber, $accountno, $itemno, $accounttype, $amount );
    }
    my $borrowernumber = $input->param('borrowernumber');
    print $input->redirect(
        "/cgi-bin/koha/members/boraccount.pl?borrowernumber=$borrowernumber");
}

sub add_accounts_to_template {
    my $borrowernumber = shift;

    my ( $total, $accts, $numaccts) = GetMemberAccountRecords( $borrowernumber );


    my $allfile = [];
    my @notify = NumberNotifyId($borrowernumber);

    my $line_id = 0;
    for my $n (@notify) {
        my $pay_loop = [];
        my ( $total , $accts, $numaccts) =
        GetBorNotifyAcctRecord( $borrowernumber, $n );
        if (!$numaccts) {
            next;
        }
        for my $acct ( @{$accts} ) {
            if ( $acct->{amountoutstanding} != 0 ) {
                $acct->{amount}            += 0.00;
                $acct->{amountoutstanding} += 0.00;
                my $line = {
                    i                 => "_$line_id",
                    itemnumber        => $acct->{itemnumber},
                    accounttype       => $acct->{accounttype},
                    amount            => sprintf('%.2f', $acct->{amount}),
                    amountoutstanding => sprintf('%.2f', $acct->{amountoutstanding}),
                    borrowernumber    => $borrowernumber,
                    accountno         => $acct->{accountno},
                    description       => $acct->{description},
                    title             => $acct->{title},
                    notify_id         => $acct->{notify_id},
                    notify_level      => $acct->{notify_level},
                };
                $line->{'net_balance'} =  1 if($acct->{'amountoutstanding'} > 0);
                $line->{'net_balance'} = undef if ((C4::Context->preference("EnableOverdueAccruedAmount")) && ($acct->{'accounttype'} eq "FU"));

                push @{ $pay_loop}, $line;
                ++$line_id;
            }
        }
        my $totalnotify = AmountNotify( $n, $borrowernumber );
        if (!$totalnotify || $totalnotify=~/^0.00/ ) {
            $totalnotify = '0';
        }
        push @{$allfile}, {
            loop_pay => $pay_loop,
            notify   => $n,
            total    => sprintf( '%.2f', $totalnotify),
        };
    }

    if ( $data->{'category_type'} eq 'C') {
        my  ( $catcodes, $labels ) =  GetborCatFromCatType( 'A', 'WHERE category_type = ?' );
        my $cnt = scalar @{$catcodes};
        if ($cnt > 1) {
            $template->param( 'CATCODE_MULTI' => 1);
        } elsif ($cnt == 1) {
            $template->param( 'catcode' =>    $catcodes->[0]);
        }
    } elsif ($data->{'category_type'} eq 'A') {
        $template->param( adultborrower => 1 );
    }

    my ($picture, $dberror) = GetPatronImage($data->{'cardnumber'});
    if ($picture ) {
        $template->param( picture => 1 );
    }

    $template->param(
        allfile        => $allfile,
        firstname      => $data->{'firstname'},
        surname        => $data->{'surname'},
        borrowernumber => $borrowernumber,
	country => $data->{'country'},
        cardnumber     => $data->{'cardnumber'},
        categorycode   => $data->{'categorycode'},
        category_type  => $data->{'category_type'},
        categoryname   => $data->{'description'},
        address        => $data->{'address'},
        address2       => $data->{'address2'},
        city           => $data->{'city'},
        zipcode        => $data->{'zipcode'},
        phone          => $data->{'phone'},
        email          => $data->{'email'},
        branchcode     => $data->{'branchcode'},
        branchname     => GetBranchName($data->{'branchcode'}),
        is_child       => ($data->{'category_type'} eq 'C'),
        total          => sprintf '%.2f', $total
    );
    return;
}

sub get_for_redirect {
    my ($name, $name_in, $money) = @_;
    my $s = q{&} . $name . q{=};
    my $value = $input->param($name_in);
    if (!defined $value) {
        $value = ($money == 1) ? 0 : q{};
    }
    if ($money) {
        $s .= sprintf '%.2f', $value;
    } else {
        $s .= $value;
    }
    return $s;
}

sub redirect_to_paycollect {
    my ($action, $line_no) = @_;
    my $redirect = "/cgi-bin/koha/members/paycollect.pl?borrowernumber=$borrowernumber";
    $redirect .= q{&};
    $redirect .= "$action=1";
    $redirect .= get_for_redirect('accounttype',"accounttype_$line_no",0);
    $redirect .= get_for_redirect('amount',"amount_$line_no",1);
    $redirect .= get_for_redirect('amountoutstanding',"out_$line_no",1);
    $redirect .= get_for_redirect('accountno',"accountno_$line_no",0);
    $redirect .= get_for_redirect('description',"description_$line_no",0);
    $redirect .= get_for_redirect('title',"title_$line_no",0);
    $redirect .= get_for_redirect('itemnumber',"itemnumber_$line_no",0);
    $redirect .= get_for_redirect('notify_id',"notify_id_$line_no",0);
    $redirect .= get_for_redirect('notify_level',"notify_level_$line_no",0);
    $redirect .= '&remote_user=';
    $redirect .= $user;
    return print $input->redirect( $redirect );
}
sub writeoff_all {
    my @wo_lines;
    my @name = $input->param;
    for (@name) {
        if (/^line_id_\d+$/) {
            push @wo_lines, $input->param($_);
        }
    }
    for my $value (@wo_lines) {
        my $accounttype    = $input->param("accounttype$value");
        my $borrowernumber = $input->param("borrowernumber$value");
        my $itemno         = $input->param("itemnumber$value");
        my $amount         = $input->param("amount$value");
        my $accountno      = $input->param("accountno$value");
        writeoff( $borrowernumber, $accountno, $itemno, $accounttype, $amount );
    }
    $borrowernumber = $input->param('borrowernumber');
    print $input->redirect(
        "/cgi-bin/koha/members/boraccount.pl?borrowernumber=$borrowernumber");
}

sub writeoff {
    my ( $borrowernumber, $accountnum, $itemnum, $accounttype, $amount ) = @_;
    my $user = $input->remote_user;
    my $dbh  = C4::Context->dbh;
    undef $itemnum unless $itemnum; # if no item is attached to fine, make sure to store it as a NULL
    my $sth =
      $dbh->prepare(
"Update accountlines set amountoutstanding=0 where accountno=? and borrowernumber=?"
      );
    $sth->execute( $accountnum, $borrowernumber );
    $sth->finish;
    
    $sth = $dbh->prepare("select max(accountno) from accountlines");
    $sth->execute;
    my $account = $sth->fetchrow_hashref;
    $sth->finish;
    $account->{'max(accountno)'}++;
    $sth = $dbh->prepare(
"insert into accountlines (borrowernumber,accountno,itemnumber,date,amount,description,accounttype)
						values (?,?,?,now(),?,'Writeoff','W')"
    );
    $sth->execute( $borrowernumber, $account->{'max(accountno)'},
        $itemnum, $amount );
    $sth->finish;
    UpdateStats( $branch, 'writeoff', $amount, '', $itemnum, '', $borrowernumber, $accountnum );

    if ( $accounttype eq 'L' && $itemnum ) {
        my $bor = "$data->{'firstname'} $data->{'surname'} $data->{'cardnumber'}";
        ModItem( { paidfor =>  "Paid for by $bor " . C4::Dates->today() }, undef, $itemnum );
    }
}
