#!/usr/bin/env perl
#
# Describe what the script/module/class does
# and why it does what it does...
#
# $Id$
# $Source$
# $Author$
# $HeadURL$
# $Revision$
# $Date$

use strict;
use warnings;

use File::Spec ();
use File::Path ();
use FindBin qw($Bin);

use lib qq($Bin/lib);
use Perldoc::Page;
use Perldoc::Page::Convert;
use Template;

my $mod = $ARGV[0] or die "Usage: $0 Some::Module\n";

my $ok = generate_html($mod, 'opera.tt');
print $ok ? "Ok!\n" : "Failed\n";

sub generate_html {
    my ($module, $tmpl_file, $output_path) = @_;

    (my $module_link = $module) =~ s/::/\//g;
    my $module_index = uc substr($module, 0, 1);

    # These modules bomb. why?
    die "$module Bombs!\n" if $module eq 'Module::Build' || $module eq 'Net::Config' || $module eq 'Tie::Hash' || $module eq 'Win32';

    my $template = Template->new(INCLUDE_PATH => "$Bin/templates");

    my %module_data;
    $module_data{pageaddress} = "$module_link.html";
    $module_data{contentpage} = 1;
    $module_data{pagename}    = $module;
    $module_data{pagedepth}   = 0 + $module =~ s/::/::/g;
    $module_data{path}        = '../' x $module_data{pagedepth};
    $module_data{breadcrumbs} = [ 
        {
            name => "Installed modules ($module_index)",
            url  => "index-modules-$module_index.html"
        }
    ];

    $module_data{content_tt}  = 'page.tt';
    $module_data{pdf_link}    = "$module_link.pdf";
    $module_data{module_az}   = ''; #\@module_az_links;

    $module_data{pod_html}    = Perldoc::Page::Convert::html($module);
    $module_data{page_index}  = Perldoc::Page::Convert::index($module);

    $output_path ||= './build';
    my $filename = File::Spec->catfile($output_path, $module_data{pageaddress});
    #check_filepath($filename);

    $template->process($tmpl_file,
        {
            perl_version => '5.10',
            download => 1,
            output_path => './build',
            project => 'Opera',
            #%Perldoc::Config::option,
            %module_data
        }, $filename
    ) or die "Failed processing $module: " . $template->error;

    return 1;
}

