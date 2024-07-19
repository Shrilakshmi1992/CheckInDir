#****************************************************************************
#!perl -w
#
#****************************************************************************
#                                                                           *
# Copyright (c) 2009 Robert Bosch GmbH, Germany                             *
#               All rights reserved                                         *
#                                                                           *
#****************************************************************************

## Executable file description data will be filled to below variable by perlBuildTool
my $buildDescription = ''; # will be patched by build tool. Do not change this line.

if($buildDescription eq ''){
    $buildDescription = "checkDir Perl script";
}


#****************************************************************************
use strict;
use warnings;
use File::Find;
use File::Basename;
use File::Spec::Functions;
use Getopt::Long qw(:config no_ignore_case bundling);
use Win32::File qw/ GetAttributes /;
use POSIX qw(strftime);
use Data::Dumper;
use IniFiles;
use ConfigureRegex;

my $scanFileNames = 0;                      # will be 0 if we scan folders only, 1 if we scan folders and files.
my $startDirectory;                         # start scanning from this folder
my $configFile;
my $projectName;                            # the project name from config file
my $curdate = strftime "%y%m%d", localtime; # Current date in yymmdd format

($startDirectory, $projectName, $configFile) = &handleArguments();   # treat the argumets passed via command line

my $logfile =  $startDirectory.".log";		# set the logfile. The logfile has the name of the passed folder.
$logfile =~ s!/|:!_!g ;						# Underscores are used instead of slashes.

## Regex for folder checking 
my $dirRegex         = ConfigureRegex::folderRegex('ConfigFile' => $configFile);
my @whiteListPatterns = ConfigureRegex::getWhiteList('ConfigFile' => $configFile);


#******************************************************************************
# Let's go and scan and log the stuff
#******************************************************************************

open (LOGGER, "> $logfile") || die("ERROR: Could not open $logfile. $!");
print LOGGER "This file contains the directories and files that do NOT match the naming conventions for the $projectName folders\n";

printToLogAndConsole("\n".gmtime().": Starting $buildDescription ...\n");
printToLogAndConsole("File scanning disabled. To enable provide -f as additional run time argument\n") unless ($scanFileNames);



my $okFoldersCounter;				# for the statistics: good and bad counters
my $nokFoldersCounter;
my $whitelistFoldersCounter;
my $expiredFoldersCounter = 0;

my $okFilesCounter;
my $nokFilesCounter;
my $skippedFilesCounter;
my $whitelistFilesCounter;
my $expiredFilesCounter = 0;

my $mainDir;
my @invalidFolders;
my @invalidFiles;
my @whiteListedItems;
my @excludedFolders;
my @expiredItems;

my @directoriesToScan = getDirectoriesToScan();

foreach my $dir (@directoriesToScan)
    {    
        $mainDir = $dir; # set main dir used during folder and file scanning globally
        
        # resets specific global data used to store information for current maindir scanning
        resetGlobalDataForMainDirScan();

        printToLogAndConsole("\nScanning $mainDir");
        printToLogAndConsole("-" x (length("Scanning $mainDir") + 2));
            
        #------------------------------------------------------------------------------
        # This is the most essential line of code in the whole script ;-)
        # Recurse through the folders and check each item (files and folders) if the
        # naming is correct.
        # Use no_chdir to avoid problems with very long Windows paths
        #------------------------------------------------------------------------------
        find( {wanted => \&validateItemName, no_chdir => 1}, $mainDir );

        print (LOGGER "\nNot ok Folders: \n") if (@invalidFolders > 0);
        foreach my $folder (sort {"\L$a" cmp "\L$b"} @invalidFolders){
            print (LOGGER "\t$folder\n");
        }

        print (LOGGER "\nNot ok Files: \n") if (@invalidFiles > 0);
        foreach my $file (sort {"\L$a" cmp "\L$b"} @invalidFiles){
            print (LOGGER "\t$file\n");
        }
        
		if (@whiteListedItems > 0) {
			printToLogAndConsole("\nWhite listed files and folders using WhiteList: ");
            foreach my $item (sort {"\L$a" cmp "\L$b"} @whiteListedItems){
                printToLogAndConsole("\t$item");
            }
		}
		
		if (@expiredItems > 0) {
			printToLogAndConsole("\nFiles\\Folders to Delete: ");
            foreach my $item (sort {"\L$a" cmp "\L$b"} @expiredItems){
                printToLogAndConsole("\t$item");
            }
		}
		
        if(@excludedFolders > 0){
            my $notCheckedFolders = join ('', map { "$_\n" } (sort {"\L$a" cmp "\L$b"} @excludedFolders));
            printToLogAndConsole("\nExcluded below folders from current scanning. From configfile this directory should be scanned separately for validating naming convention\n$notCheckedFolders");
        }

        printToLogAndConsole("\n");
        printStatistics();
        printToLogAndConsole("\n\n");
        
    } # scan next directory


printToLogAndConsole(gmtime().": Scanning completed...\n");
close (LOGGER);

#****************************************************************************
# END main
#****************************************************************************


#****************************************************************************
# This is the validation of the found items
# We scan directories or files, check if they match and write the mismatching 
# ones to the LOGFILE.
#****************************************************************************
sub validateItemName
{
    my $item = $File::Find::name;               # This can either be a folder name or a file name
   
    if (not $scanFileNames)
    {
        return unless -d $item;	# do nothing if the detected Item is NOT a Directory ("-d"). I.e. return if the item is a file.
                                 # This is done here simply for speeding up the item handling.
    }
    return if $item eq $mainDir;	# do nothing for the start directory

	if ($item =~ /\_EXPD(\d{6})(\.(\w+))?$/) {
		my $expDate = $1;
		if ($expDate < $curdate) {
			push @expiredItems,$item;
			if (-d $item) {
				$expiredFoldersCounter++;
			} else {
				$expiredFilesCounter++;
			}
		}
	}
	
    if (grep {/\Q$item\E/i} @directoriesToScan ){
        $File::Find::prune = 1;
        push (@excludedFolders,$item);
        return;
    }
	
	if (grep { "$item" =~ /$_/i } @whiteListPatterns) {
		push @whiteListedItems, $item;
		if (-d $item) {
			$whitelistFoldersCounter++;
		} else {
			$whitelistFilesCounter++;
		}
		return;
    }
	
	if ( -d $item)     # item is a folder
	{
		if ($item =~ /(.*\.\w+)\(\d+\)$/) {
			return; # Could be revision set, hence skipping naming check.
		}
		&verifyDirectoryName();
	}
	else               # item is a file
	{
		&verifyFileName();
	}
}

#****************************************************************************
# Verify the directory name
#****************************************************************************
sub verifyDirectoryName
{
    print "\n" if $scanFileNames;
    
    # The main directory is put in the quote environment (\Q ... \E) as it can contain Perl special
    # characters like the dollar sign.
    # Example: K:\DfsDE\DIV\CS\DE_CS$\Prj\PS\Line\Hardware\EHW
	if ($File::Find::name !~ /^(\Q$mainDir\E)$dirRegex$/)
	{	
		# Folders not ok
        push(@invalidFolders, $File::Find::name);
		print (">>>Folder: $File::Find::name\n");
		$nokFoldersCounter++;
	}
	else
	{	# Folders ok
		print ("ok Folder:$File::Find::name\n");
		$okFoldersCounter++;
	}
    
}

#****************************************************************************
# Verify the file name
#****************************************************************************
sub verifyFileName
{
	my $currentFile = $_;
	my ($currentFileName,$currentFilePath) = fileparse($currentFile);
    my $spaces = " " x 4;
	my $attributes = 0;
	my $IS_HIDDEN = 2;		# The HIDDEN attribute of a file or directory is "2" in Win.

    GetAttributes( $currentFile, $attributes );	# check if the file is hidden. If yes, skip it. (returnedAttributes will be set to the OR-ed combination of the filename attributes)
    if ( $attributes & $IS_HIDDEN)
    {
    	print "$spaces Hidden file $currentFile skipped from naming check.\n";
    	$skippedFilesCounter++;
    }
    else	# file is not hidden
    {
       if (&isException($currentFileName) )
       {
          print ("$spaces File name exception found. Skipping file naming check for $currentFile.\n");
		  $skippedFilesCounter++;
       }
       else		# no exception found, therefore proces it
       {
			# The main directory is put in the quote environment (\Q ... \E) as it can contain Perl special
			# characters like the dollar sign.
			# Example: K:\DfsDE\DIV\CS\DE_CS$\Prj\PS\Line\Hardware\EHW
           
		   if ($currentFilePath =~ m!^(\Q$mainDir\E)$dirRegex?/?$!)	# again check: path is correct?
		   {
			  my $fileRegex = ConfigureRegex::fileRegex('ConfigFile' => $configFile,'currentFilePath' => $currentFilePath);
              
              my $configFileName = basename($configFile);
              
			  # Now check if the calculated file name matches the real one (=$currentFileName) or is named similar to input config file.
			  if (($currentFileName =~ /\A$fileRegex\Z/) || (lc($currentFileName) eq lc($configFileName)))
			  {
				 # File Name ok
				 print ("$spaces ok Filename: $currentFileName\n");
				 $okFilesCounter++;
			  }
			  else
			  {
				 # File name not ok
				 print ("$spaces >>> Filename: $currentFileName\n");
                 push(@invalidFiles,$currentFile);
				 $nokFilesCounter++;
			  }
		   }
		   else		# path not correct
		   {
			  print ("$spaces Path not correct. Skipping file naming check for $currentFileName.\n");
			  $skippedFilesCounter++;
		   }
	   }
	}

}


#****************************************************************************
# Handle exceptions: e.g. ignore files that are shortcuts (*.lnk)
#****************************************************************************
sub isException
{
	my $file = shift;
	my @extensionsToIgnore = qw / lnk /;
	my $exceptionFound = 0;
	
	foreach my $extensionToIgnore (@extensionsToIgnore)
	{
		if ( $file =~ m!\.(\w+)$!)	# get the extension for <filename>.<ext> (e.g. myfile.lnk)
		{
			my $currentExtension = $1;
			if ( $currentExtension eq $extensionToIgnore )
			{
				# skip it
				$exceptionFound = 1;
				last;
			}
			else
			{
				# do nothing, ext is allowed
				$exceptionFound = 0;
			}
		}
		else
		{
			# not a file that has an extension. Ignore it.
			$exceptionFound = 0;
			last;
		}
	}	
	return $exceptionFound;
}


#****************************************************************************
# Setup main directories for scanning for naming convention
#****************************************************************************
sub getDirectoriesToScan {
    my @dirsToScan = ($startDirectory);
    
    my $section = "SeparateFolder";
    my $parameter = "SEP_FLDR";

    my $ro_checkDirIni = IniFiles->new ( -file => $configFile );    
    my @ra_sepParam = $ro_checkDirIni->Parameters ( $section );
    
    my $invalidParams = join (', ', grep {$_ !~ /\A$parameter\Z/} @ra_sepParam);
    die ("ERROR: Config file section $section contains invalid parameters $invalidParams\n") if ($invalidParams ne '');
    
    my $value = $ro_checkDirIni->val( "SeparateFolder", "SEP_FLDR" );
    my @ra_sepfldr =  grep { /\S/ } split(/,/,$value);
    
    (my $mainDir = $startDirectory) =~ s/(.*)\/\Z/$1/; # Required without / at last. Adding below

    foreach my $sepfldr (@ra_sepfldr){
        $sepfldr =~ s/^\s+|\s+$//g; # remove whitespaces from starting and end
        my $dir = $mainDir."/".$sepfldr;
        
        if ( not -d $dir ){
            printToLogAndConsole("WARNING: ConfigFile specified SeparateFolder for scanning $dir does not exists \n");
        }else{
            push(@dirsToScan,$dir);
        }
    }
    
    return @dirsToScan;
}

#****************************************************************************
# Get the project name from the input config file
#****************************************************************************
sub getProjectName {
    my $section = "ProjectName";
    my $parameter = "Name";

    my $ro_checkDirIni = IniFiles->new ( -file => $configFile );    
    my @ra_prjName = $ro_checkDirIni->Parameters ( $section );
    
    my $invalidParams = join (', ', grep {$_ !~ /\A$parameter\Z/} @ra_prjName);
    die ("ERROR: Config file section $section contains invalid parameters $invalidParams\n") if ($invalidParams ne '');

    my $prjNameFromIniFile = $ro_checkDirIni->val( $section, $parameter );
    
	return $prjNameFromIniFile;
}


#****************************************************************************
# Check the given arguments and do the needed settings
#****************************************************************************
sub handleArguments {

    my %opts;

    #------------------------------------------------------------------------
	# check that only allowed parameters are given
	if(GetOptions( \%opts, 'h|help','f|files', 'c|config=s' )!= 1)
	{        
	   &printUsage();
	   exit(0);
	}
    #------------------------------------------------------------------------
	# handle the "help" argument
	if (exists $opts{"h"})
	{
	   &printUsage();
	   exit(0);
	}
    
    #------------------------------------------------------------------------
	# handle the "config" argument
    if(not exists $opts{"c"})
    {
      &printUsage();
	  die ("\nERROR: Please provide configuration file as input!\n");
    }

    $configFile = $opts{"c"};
    $configFile =~ s!\\!/!g ;
    if( not -f $configFile ) {
        die ("ERROR: Provided configuration file $configFile does not exists\n$!\n");
    }elsif ($configFile !~ /\.ini$/){
        die ("ERROR: Provided configuration file $configFile is not ini file\n");
    }
    
    $projectName = getProjectName();
    
    #------------------------------------------------------------------------
    # get the start directory where to start scanning
	$startDirectory = $ARGV[0]; 				# get the parameters
	if (not defined $startDirectory) {			# check if arguments were passed
			&printUsage;
			die ("\nERROR: Please give a folder name as argument!\n");
	}
	$startDirectory =~ s/\\/\//g ;				# switch every backslash to slash. Just to be safe and consistent.
    $startDirectory =~ s/\/+$//;            # remove slashes from last if it exists
    $startDirectory =~ s/"//g; # Fix for input folder with space and \ at last ex: "C:\Test\Input Folder\"
    $startDirectory .= "/" if ($startDirectory =~ /:\Z/); # Fix for search in direct network drive ex: V:, U:

	if ( not -d $startDirectory) {				# Verify if the start folder exists
		die ("ERROR: $!\nPlease check the passed argument ($startDirectory)!\n");
	}
    #------------------------------------------------------------------------
	# handle the "also scan file names" argument
	if (exists $opts{"f"})
	{
	   $scanFileNames = 1;
	}
    #------------------------------------------------------------------------
	return ($startDirectory, $projectName, $configFile);
}

#****************************************************************************
# To print same data in log and console
#****************************************************************************
sub printToLogAndConsole{
    my ($dataToPrint) = @_;
    print LOGGER $dataToPrint."\n";
    print $dataToPrint."\n";
}

#****************************************************************************
# To print statistics after maindir scanning
#****************************************************************************
sub printStatistics{

my $statistics = sprintf(
" Statistics:      Folder       File
--------------   ----------   --------
 OK:               %-4d         %-4d
 Not ok:           %-4d         %-4d
 Skipped file:                  %-4d
 White List:       %-4d         %-4d
--------------   ----------   --------
 Sum:              %-4d         %-4d
" , $okFoldersCounter,
    $okFilesCounter,
    $nokFoldersCounter,
    $nokFilesCounter,
    $skippedFilesCounter,
	$whitelistFoldersCounter,
	$whitelistFilesCounter,
    $okFoldersCounter+$nokFoldersCounter+$whitelistFoldersCounter,
    $okFilesCounter+$nokFilesCounter+$skippedFilesCounter+$whitelistFilesCounter
);
    $statistics .= sprintf(" Files to Delete   %-4d         %-4d"
  ,	$expiredFoldersCounter,
    $expiredFilesCounter
   ) if  $expiredFoldersCounter + $expiredFilesCounter > 0;

print LOGGER $statistics;
print $statistics;   
    
}

#****************************************************************************
# Resets the global data used to store mainDir scan information for 
# statistics and log file to default value.
# To be called before starting mainDir scanning
#****************************************************************************
sub resetGlobalDataForMainDirScan {
    
    # for the statistics
    $okFoldersCounter       = 0;				
    $nokFoldersCounter      = 0;
	$whitelistFoldersCounter= 0;

    $okFilesCounter       = 0;
    $nokFilesCounter      = 0;
    $skippedFilesCounter  = 0;
	$whitelistFilesCounter= 0;
    
    # Hold invalid folders and files for log file
    @invalidFolders  = ();
    @invalidFiles    = ();
    @excludedFolders = ();
	@whiteListedItems= ();
}

#****************************************************************************
# Some helptext
#****************************************************************************
sub printUsage {
    
print "
Tool for checking folders/files if they correspond to the project configured naming conventions format.

Usage:
------
checkDir [-h][-f] -c <configurationFile> <topLevelProjectFolder> 

Mandatory arguments:
-------------------
-c,--config Project specific configuration file containing formats for folder and files naming 

Optional arguments:
------------------
-h,--help    Print this help text and exit
-f,--files   Also scan for correct file names.
             If a file is located in a folder that has no correct folder naming,
             all the files in that folder are skipped and not scanned.

Output:
-------
Results are stored in <topLevelProjectFolder-Name>.log in the current folder.


Examples:
---------
scan for correct folder names
-----------------------------------------
checkDir -c C:\\temp\\CheckDirConfig.ini N:\\Projekte\\AB10
checkDir --config C:\\temp\\CheckDirConfig.ini N:\\Projekte\\AB15


scan for correct folder and file names
-----------------------------------------
checkDir -f -c C:\\temp\\CheckDirConfig.ini N:\\Projekte\\AB15
checkDir --files --config C:\\temp\\CheckDirConfig.ini N:\\Projekte\\AB10


Build $buildDescription
";
}


1;
########################################################################
# Build information if exe needs to be created directly using perl2exe
########################################################################

# The following statements are included to build an *.exe with perl2exe:
#perl2exe_include Encode/Unicode
#perl2exe_include XML/Parser/Style/Tree
#perl2exe_include "unicore/Heavy.pl"
#perl2exe_include "unicore/To/Cf.pl"
#perl2exe_include IO/Uncompress/Bunzip2

#perl2exe_info CompanyName=Robert Bosch GmbH
#perl2exe_info FileDescription=checkDir.exe
#perl2exe_info FileVersion=2.0.0.0
#perl2exe_info ProductVersion=0.0.0.0


