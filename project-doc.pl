#!/usr/bin/env perl
#
# Generate project-wide html documentation from pod
#

use strict;
use warnings;
use feature 'say';

use Config;
use Data::Dumper;
use File::Basename;
use File::Find;
use File::Path;
use Shell ();
use File::Spec::Functions;
use FindBin qw/$Bin/;
use lib './lib';
use Getopt::Long;
use Template;
use Perldoc::Config;

use constant TRUE  => 1;
use constant FALSE => 0;

use vars qw/$processing_state/;
use vars qw/%manpage_pods/;

eval <<EOT;
use Perldoc::Convert::html;
use Perldoc::Function;
use Perldoc::Function::Category;
use Perldoc::Page;
use Perldoc::Page::Convert;
use Perldoc::Section;  
EOT

die $@ if $@;


my %opt = parse_options();

# Get list of project modules
$opt{scan_dirs} ||= '';
my @dirs = split ':' => $opt{scan_dirs};
my @modules = find_modules(@dirs);

debug("Found " . scalar(@modules) . " modules");

# Generate js, static and html files
generate_javascript_files (\%opt, @modules);
generate_static_files     (\%opt, @modules);
generate_html_files       (\%opt, @modules);
generate_perlfunc_files   (\%opt, @modules);

say "Done!";
exit 0;



sub modules_az_links {
    my (@module_list) = @_;

    my @module_az_links;

    foreach my $module_index ('A'..'Z') {
        my $link;
        if (grep {/^$module_index/} @module_list) {
            $link = "index-modules-$module_index.html";
        } 
        push @module_az_links, {letter=>$module_index, link=>$link};
    }

    return @module_az_links;
}

sub generate_html_files {
    my ($opt, @module_list) = @_;

    # XXX Rename to module_links
    my %core_modules;

    #--Compute link addresses -----------------------
    foreach my $module (grep {/^[A-Z]/} @module_list) {
      my $link = $module;
      $link =~ s!::!/!g;
      $link .= '.html';
      $core_modules{$module} = $link;
    }

    debug("Core modules list generated (" . scalar(keys(%core_modules)) . " modules found).");

    my @module_az_links = modules_az_links(@module_list);

    $opt->{last_update} = last_update_timestamp();

=cut
    #--Create index pages------------------------------------------------------

    foreach my $section (Perldoc::Section::list()) {

      debug("Generating documentation section $section");

      my %index_data;
      my $template             = Template->new(INCLUDE_PATH => TT_INCLUDE_PATH);
      $index_data{pagedepth}   = 0;
      $index_data{path}        = '../' x $index_data{pagedepth};
      $index_data{pagename}    = Perldoc::Section::name($section);
      $index_data{pageaddress} = "index-$section.html";
      $index_data{content_tt}  = 'section_index.tt';
      $index_data{module_az}   = \@module_az_links;

      foreach my $page (Perldoc::Section::pages($section)) {
        (my $page_link = $page) =~ s/::/\//g;
        push @{$index_data{section_pages}},{name=>$page, link=>"$page_link.html",title=>Perldoc::Page::title($page)};
      }

      my $htmlfile = catfile($Perldoc::Config::option{output_path},$index_data{pageaddress});
      check_filepath($htmlfile);
      $template->process($tmpl_file, {%Perldoc::Config::option, %index_data},$htmlfile) || die $template->error;

      # For every index page, create the corresponding man pages
      debug('Section pages: (' . join(', ', Perldoc::Section::pages($section)) . ')');

      foreach my $page (Perldoc::Section::pages($section)) {
        next if ($page eq 'perlfunc');  # 'perlfunc' will be created later
        my %page_data;
        (my $page_link = $page) =~ s/::/\//g;
        $page_data{pagedepth}   = 0 + $page =~ s/::/::/g;
        $page_data{path}        = '../' x $page_data{pagedepth};
        $page_data{pagename}    = $page;
        $page_data{pageaddress} = "$page_link.html";
        $page_data{contentpage} = 1;
        $page_data{module_az}   = \@module_az_links;
        $page_data{breadcrumbs} = [ {name=>Perldoc::Section::name($section), url=>"index-$section.html"} ];
        $page_data{content_tt}  = 'page.tt';
        $page_data{pdf_link}    = "$page_link.pdf";
        debug("    - Before convert::html $page");

        # 're' causes the script to silently abort for no apparent reason
        next if $page eq 're' || $page eq 'instmodsh';

        $page_data{pod_html}    = Perldoc::Page::Convert::html($page);
        $page_data{pod_html}    =~ s!<(pre class="verbatim")>(.+?)<(/pre)>!autolink($1,$2,$3,$page_data{path})!sge if ($page eq 'perl');
        $page_data{page_index}  = Perldoc::Page::Convert::index($page);

        my $filename  = catfile($Perldoc::Config::option{output_path},$page_data{pageaddress});    
        debug("    - Generating page $page ($filename)");

        check_filepath($filename);

        $template->process($tmpl_file,{%Perldoc::Config::option, %page_data},$filename) || die "Failed processing $page\n".$template->error;
      }

    }

=cut

    # ----------------------------------------------------
    debug("Generating modules index...");

    foreach my $module_index ('A'..'Z') {
        my %page_data;
        my $template            = Template->new(INCLUDE_PATH => $opt->{template_path});
        $page_data{pagedepth}   = 0;
        $page_data{path}        = '../' x $page_data{pagedepth};
        $page_data{pagename}    = qq{Core modules ($module_index)};
        $page_data{pageaddress} = "index-modules-$module_index.html";
        $page_data{breadcrumbs} = [ ];
        $page_data{content_tt}  = 'module_index.tt';
        $page_data{module_az}   = \@module_az_links;

        foreach my $module (grep {/^$module_index/} sort {uc $a cmp uc $b} @module_list) {
            (my $module_link = $module) =~ s/::/\//g;
            $module_link .= '.html';
            my $title;
            eval { $title = Perldoc::Page::title($module) };
            push @{$page_data{module_links}}, {
                name=>$module,
                title=>$title,
                url=>$module_link
            };
        }

        my $filename = catfile($opt->{output_path}, $page_data{pageaddress});
        debug("Generating modules index $module_index ($filename)");
        check_filepath($filename);
      
        $template->process($opt->{template}, {%$opt, %page_data},$filename)
            or die $template->error;

        my $section_title = $opt->{title} || 'Untitled project';

        foreach my $module (grep {/^$module_index/} @module_list) {
      
            my %module_data;
            (my $module_link = $module) =~ s/::/\//g;
          
            #warn "    - module $module\n";

            $module_data{pageaddress} = "$module_link.html";
            $module_data{contentpage} = 1;
            $module_data{pagename}    = $module;
            $module_data{pagedepth}   = 0 + $module =~ s/::/::/g;
            $module_data{path}        = '../' x $module_data{pagedepth};
          
            $module_data{breadcrumbs} = [ {
                name => "$section_title ($module_index)",
                url  => "index-modules-$module_index.html"
            } ];
            $module_data{content_tt}  = 'page.tt';
            $module_data{pdf_link}    = "$module_link.pdf";
            $module_data{module_az}   = \@module_az_links;
          
            eval {
                $module_data{pod_html}    = Perldoc::Page::Convert::html($module);
                $module_data{page_index}  = Perldoc::Page::Convert::index($module);
            } or do {
                warn "FAILED CONVERTING $module: $@\n";
            };
          
            my $filename = catfile($opt->{output_path}, $module_data{pageaddress});
            check_filepath($filename);
          
            $template->process($opt->{template}, {
                %$opt, %module_data
            }, $filename) || die "Failed processing $module\n".$template->error;
      
        }
    }

    return;
}


sub generate_perlfunc_files {
    my ($opt, @module_list) = @_;

    #--------------------------------------------------------------------------
    #--Perl functions----------------------------------------------------------
    #--------------------------------------------------------------------------

    #--Generic variables-------------------------------------------------------

    my %function_data;
    my $function_template = Template->new(INCLUDE_PATH => $opt->{template_path});

    #--Index variables---------------------------------------------------------

    $function_data{pagedepth}   = 0;
    $function_data{path}        = '../' x $function_data{pagedepth};


    #--Create A-Z index page---------------------------------------------------

    $function_data{pageaddress} = 'index-functions.html';
    $function_data{pagename}    = 'Perl functions A-Z';
    $function_data{breadcrumbs} = [ {name=>'Language reference', url=>'index-language.html'} ];
    $function_data{content_tt}  = 'function_index.tt';
    $function_data{module_az}   = [ modules_az_links(@module_list) ];

    debug("Generating documentation for functions...");

    foreach my $letter ('A'..'Z') {
      my ($link,@functions);
      if (my @function_list = grep {/^[^a-z]*$letter/i} sort (Perldoc::Function::list())) {
        $link = "#$letter";
        foreach my $function (@function_list) {
          (my $url = $function) =~ s/[^\w-].*//i;
          $url .= '.html';
          my $description = Perldoc::Function::description($function);
          push @functions,{name=>$function, url=>$url, description=>$description};
        }
      } 
      push @{$function_data{function_az}}, {letter=>$letter, link=>$link, functions=>\@functions};
    }

    my $filename = catfile($opt->{output_path},$function_data{pageaddress});
    check_filepath($filename);

    $function_template->process($opt->{template}, {%$opt, %function_data},$filename)
        or die "Failed processing function A-Z\n".$function_template->error;


    #--Create 'functions by category' index page-------------------------------

    $function_data{pageaddress} = 'index-functions-by-cat.html';
    $function_data{pagename}    = 'Perl functions by category';
    $function_data{content_tt}  = 'function_bycat.tt';

    foreach my $category (Perldoc::Function::Category::list()) {
      my $name = Perldoc::Function::Category::description($category);
      (my $link = $name) =~ tr/ /-/;
      my @functions;
      foreach my $function (sort (Perldoc::Function::Category::functions($category))) {
        (my $url = $function) =~ s/[^\w-].*//i;
        $url .= '.html';
        my $description = Perldoc::Function::description($function);
        push @functions,{name=>$function, url=>$url, description=>$description};
      }
      push @{$function_data{function_cat}},{name=>$name, link=>$link, functions=>\@functions};
    }

    $filename = catfile($opt->{output_path},$function_data{pageaddress});
    check_filepath($filename);

    $function_template->process($opt->{template}, {%$opt, %function_data}, $filename)
        or die "Failed processing functions by category\n".$function_template->error;

    #--Create 'perlfunc' page--------------------------------------------------

    $function_data{pageaddress} = 'perlfunc.html';
    $function_data{contentpage} = 1;
    $function_data{pagename}    = 'perlfunc';
    $function_data{content_tt}  = 'function_page.tt';
    $function_data{pdf_link}    = "perlfunc.pdf";
    $function_data{pod_html}    = Perldoc::Page::Convert::html('perlfunc');
        
    $filename = catfile($opt->{output_path},$function_data{pageaddress});
    check_filepath($filename);

    $function_template->process($opt->{template},{%$opt, %function_data}, $filename)
        or die "Failed processing perlfunc\n".$function_template->error;


    #--Function variables------------------------------------------------------

    undef $function_data{pdf_link};
    $function_data{pagedepth}   = 1;
    $function_data{path}        = '../' x $function_data{pagedepth};


    #--Create individual function pages----------------------------------------

    debug("Generating perlfunc documentation...");

    foreach my $function (Perldoc::Function::list()) {
        local $processing_state = 'functions';
        my $function_pod = Perldoc::Function::pod($function);
        $function =~ s/[^\w-].*//i;
        warn ("No Pod for function '$function'\n") unless ($function_pod);
        chomp $function_pod;
        
        $function_data{pageaddress} = "functions/$function.html";
        $function_data{pagename}    = $function;
        $function_data{breadcrumbs} = [ {name=>'Language reference', url=>'index-language.html'},
                                        {name=>'Functions', url=>'index-functions.html'} ];
        $function_data{pod_html}    = Perldoc::Convert::html::convert('function::',$function_pod);
        $function_data{pod_html} =~ s!(<a href=")#(\w+)(">)!Perldoc::Function::exists($2) ? "$1../functions/$2.html$3" : "$1#$2$3"!ge;
      
        $filename  = catfile($opt->{output_path},$function_data{pageaddress});
        check_filepath($filename);
      
        $function_template->process($opt->{template},{%$opt, %function_data},$filename)
          or die "Failed processing perlfunc\n".$function_template->error;
    }

}

sub find_modules {

    my (@dirs) = @_;
    my $dirs = join(' ', map { q(') . $_ . q(') } @dirs);

    my @modules = `grep -r '^package .*;' $dirs | awk '{ print \$2 }' 2>/dev/null | egrep '[A-Z]' | sort | uniq | perl -ple 's/;\$//'`;
    chomp for @modules;

    return @modules;
}

sub extract_title {
    my ($page) = @_;

    my $title;

    eval {
        $title = Perldoc::Page::title($page) || "Untitled module $page";
    } or do {
        return "No pod for $page !!";
    };

    $title =~ s/\\/\\\\/g;
    $title =~ s/"/\\"/g;
    $title =~ s/C<(.*?)>/$1/g;
    $title =~ s/\n//sg;

    return $title; 
}

sub generate_javascript_files {
    my ($opt, @module_list) = @_;

    #--Create indexPod.js------------------------------------------------------
    my @pods;
    for my $page (@module_list) {
        push @pods,{
            name => $page,
            description => extract_title($page)
        };
    }

    my $jsfile   = catfile($opt->{output_path},'static','indexPod.js');
    my $template = Template->new(INCLUDE_PATH => $opt->{template_path});
    $template->process('indexpod-js.tt',{
        %{ $opt },
        pods=>\@pods
    }, $jsfile)
        or die $template->error;

    #--Create indexModules.js--------------------------------------------------
    my @modules;
    foreach my $page (@module_list) {
        if (my $title = extract_title($page)) {
            push @modules,{name=>$page, description=>$title};
        }
    }

    $jsfile = catfile($opt->{output_path}, 'static', 'indexModules.js');

    $template->process('indexmodules-js.tt', {
        %{ $opt },
        modules => \@modules
    }, $jsfile)
        or die $template->error;

=cut
    #--Create indexFunctions.js------------------------------------------------

    my @functions;
    foreach my $function (Perldoc::Function::list()) {
      my $description = Perldoc::Function::description($function) || warn "No description for $function";
      $description =~ s/\\/\\\\/g;
      $description =~ s/"/\\"/g;
      $description =~ s/C<(.*?)>/$1/g;
      $description =~ s/\n//sg;
      
      push @functions,{name=>$function, description=>$description};
    }

    $jsfile = catfile($Perldoc::Config::option{output_path},'static','indexFunctions.js');
    $template->process('indexfunctions-js.tt',{%Perldoc::Config::option, functions=>\@functions},$jsfile) || die $template->error;

    #--Create indexFAQs.js-----------------------------------------------------

    my @faqs;
    foreach my $section (1..9) {
      my $pod    = Perldoc::Page::pod("perlfaq$section");
      my $parser = Pod::POM->new();
      my $pom    = $parser->parse_text($pod);

      foreach my $head1 ($pom->head1) {
        foreach my $head2 ($head1->head2) {
          my $title = $head2->title->present('Pod::POM::View::Text');
          $title =~ s/\n/ /g;
          $title =~ s/\\/\\\\/g;
          $title =~ s/"/\\"/g;
          push @faqs,{section=>$section,name=>$title};
        }
      }
    }

    $jsfile = catfile($Perldoc::Config::option{output_path},'static','indexFAQs.js');
    $template->process('indexfaqs-js.tt',{%Perldoc::Config::option, faqs=>\@faqs},$jsfile) || die $template->error;
=cut

    return;
}

sub parse_options {

    #--Set config options------------------------------------------------------

    my %specifiers = (
        'output-path' => '=s',
        'template'    => '=s',
        'template-path'=>'=s',
        'pdf'         => '!',
        'perl'        => '=s',
        'project'     => '=s',
        'title'       => '=s',
        'scan-dirs'   => '=s',
    );

    my %options;
    GetOptions( \%options, optionspec(%specifiers) );

    # Used in the templates to generate relative links
    $options{download} = 1;

    #--Check mandatory options have been given---------------------------------
    my @mandatory_options = qw(output-path);

    foreach (@mandatory_options) {
        (my $option = $_) =~ tr/-/_/;
        unless ($options{$option}) {
            die "Option '$_' must be specified!\n";
        }
    }

    my $tmpl_path = $options{template_path} ||= './docs/templates';
    my $tmpl_file = $options{template}      ||= 'default.tt';

    #--Create output path folder if it doesn't exist---------------------------

    unless (-d $options{output_path}) {
        mkpath($options{output_path}, 0, 0755);
    }

    %Perldoc::Config::option = (%Perldoc::Config::option, %options);

    #--Check if we are using a different perl----------------------------------

    if ($options{perl}) {
      #warn "Setting perl to $options{perl}\n";
      my $version_cmd  = 'printf("%vd",$^V)';
      my $perl_version = `$options{perl} -e '$version_cmd'`;
      my $inc_cmd      = 'print "$_\n" foreach @INC';
      my $perl_inc     = `$options{perl} -e '$inc_cmd'`;
      my $bin_cmd      = 'use Config; print $Config{bin}';
      my $perl_bin     = `$options{perl} -e '$bin_cmd'`;
      
      $Perldoc::Config::option{perl_version}  = $perl_version;
      $Perldoc::Config::option{perl5_version} = substr($perl_version,2);
      $Perldoc::Config::option{inc}           = [split /\n/,$perl_inc];
      $Perldoc::Config::option{bin}           = $perl_bin;
      
      #warn Dumper(\%Perldoc::Config::option);
    }

    return %Perldoc::Config::option;

}

sub generate_static_files {
    my ($opt, @module_list) = @_;

    $opt->{last_update} = last_update_timestamp();

    #--Copy static files------------------------------------------------------

    my $static_path = catdir($opt->{output_path}, 'static');
    mkpath($static_path) unless -d $static_path;

    my $tmpl_path = $opt->{template_path};

    Shell::cp('-r', "$tmpl_path/static/*",     $static_path);
    Shell::cp('-r', "$tmpl_path/javascript/*", $static_path);

    #--Process static html files with template--------------------------------

    my @module_az_links;
    foreach my $module_index ('A'..'Z') {
      my $link;
      if (grep {/^$module_index/} @module_list) {
        $link = "index-modules-$module_index.html";
      } 
      push @module_az_links, {letter=>$module_index, link=>$link};
    }

    my $process = create_template_function(
        #templatefile => $templatefile,
        opt => $opt,
        variables    => {
            module_az => \@module_az_links,
            %{ $opt }
        },
    );

    warn "Searching in $tmpl_path/static-html";
    find( {wanted=>$process, no_chdir=>1}, "$tmpl_path/static-html" );

    #-------------------------------------------------------------------------


}

sub last_update_timestamp {

    my $date = sprintf("%02d",(localtime(time))[3]);
    my $month = qw/
        January
        February
        March
        April
        May
        June
        July
        August
        September
        October
        November
        December /[(localtime(time))[4]];
    my $year = (localtime(time))[5] + 1900;
    return "$date $month $year";
}

sub create_template_function {
    my %args = @_;

    my $opt = $args{opt};
    my $title = $args{variables}->{title};

    return sub {

        #warn "Process called: $_";
        return unless (/(\w+)\.html$/);

        my $page = $1;
        local $/ = undef;

        my $template = Template->new(
            INCLUDE_PATH => [$opt->{template_path}, '.'],
            #ABSOLUTE     => 1,
            RELATIVE     => 1,
        );
        my $depth = () = m/\//g;
      
        my %titles = (
            index       => $title || 'Untitled project documention',
            search      => 'Search results',
            preferences => 'Preferences',
        );
      
        my %breadcrumbs = (
            index       => 'Home',
            search      => '<a href="index.html">Home</a> &gt; Search results',
            preferences => '<a href="index.html">Home</a> &gt; Preferences',
        );
      
        my %variables          = %{$args{variables}};
      
        $depth--;
        $variables{path}       = '../' x ($depth - 1);
        $variables{pagedepth}  = $depth - 1;
        $variables{pagename}   = $titles{$page} || $page;
        $variables{breadcrumb} = $breadcrumbs{$page} || $page;
        $variables{content_tt} = $File::Find::name;

        my $output_filename = catfile($opt->{output_path}, basename($_));
        #my $cwd = Cwd::cwd();
        #warn "Writing $output_filename (output_path: $opt->{output_path}, cwd: $cwd, template: $opt->{template})";

        $template->process(
            $opt->{template}, {
                %{ $opt },
                %variables
            },
            $output_filename
        ) or die "!! Failed processing $page\n" . $template->error;

    }

}

#--------------------------------------------------------------------------

sub autolink {
    my ($start,$txt,$end,$linkpath) = @_;
    $txt =~ s!\b(perl\w+)\b!(Perldoc::Page::exists($1))?qq(<a href="$linkpath$1.html">$1</a>):$1!sge;
    return "<$start>$txt<$end>";
}

sub check_filepath {
    my $filename  = shift;
    my $directory = dirname($filename);
    mkpath $directory unless (-d $directory);
}

sub escape {
    my $data = shift;
    $data =~ s/([^a-z0-9])/sprintf("%%%02x",ord($1))/egi;
    return $data;
}

sub optionspec {
    my %option_specs = @_;
    my @getopt_list;
    while (my ($option_name,$spec) = each %option_specs) {
        (my $variable_name = $option_name) =~ tr/-/_/;
        (my $nospace_name  = $option_name) =~ s/-//g;
        my $getopt_name = ($variable_name ne $option_name) ? "$variable_name|$option_name|$nospace_name" : $option_name;
        push @getopt_list,"$getopt_name$spec";
    }
    return @getopt_list;
}

sub debug {
    my $verbose = 1;
    print STDERR @_, "\n" if $verbose;
}

