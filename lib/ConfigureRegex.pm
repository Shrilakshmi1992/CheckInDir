package ConfigureRegex;

use strict;
use warnings;
use IniFiles;
use File::Basename;
use Data::Dumper;

my %prefixSubfolderReg = ();

#****************************************************************************
# Private subfunction
#
# To configure regex syntax commonly used by folder and file Regex builder
#****************************************************************************
sub _commonSyntax
{
    my ($data,$section,$parameter) = @_;
    my $syntax = '';
    my $seperatorBetweenSyntax;
    
    # warn "data: $data\n";
    if($data =~ '(<d(\d+|n)>)') # Config file pattern <dn>
     {
         if($2 eq 'n'){
           $syntax.='\d+';
         }elsif($2 eq '0'){
             die ("ERROR: Config file section $section parameter $parameter has 0 digits $1. Specify correct number starting from 1 \n");
         }else{
           $syntax.='\d{'.$2.'}';    
         }
     }
     elsif ($data =~ '(<c(\d+|n)>)') # Config file pattern <cn>
     {
         if($2 eq 'n'){
           $syntax.='[a-z]+';
         }elsif($2 eq '0'){
             die ("ERROR: Config file section $section parameter $parameter specify 0 characters $1. Specify correct number starting from 1 \n");
         }else{
         $syntax.='[a-z]{'.$2.'}';
         }
     }
     elsif ($data =~ '(<C(\d+|n)>)') # Config file pattern <Cn>
     {
         if($2 eq 'n'){
           $syntax.='[A-Z]+';
         }elsif($2 eq '0'){
             die ("ERROR: Config file section $section parameter $parameter specify 0 characters $1. Specify correct number starting from 1 \n");
         }else{
         $syntax.='[A-Z]{'.$2.'}';
         }
     }
     elsif ($data =~ '(<(cC|Cc)(?=\d+|n)>)') # Config file pattern <Ccn> or <cCn>
     {
         if($3 eq 'n'){
           $syntax.='[A-Za-z]+';
         }elsif($3 eq '0'){
             die ("ERROR: Config file section $section parameter $parameter specify 0 characters $1. Specify correct number starting from 1 \n");
         }else{
         $syntax.='[A-Za-z]{'.$3.'}';
         }
     }
     elsif ($data =~ /(<.*>)/) # If Config file contains pattern enclosed in <> which is not allowed
     {
         die ("ERROR: Config file section $section parameter $parameter contains invalid pattern enclosed in <>: $1 \n");
     }
     else{
         # Any other data specified which is not in enclosed <>
         my @ra_valCharacters = split(//,$data); # split the data in chunks
         $seperatorBetweenSyntax = '';
         
         foreach my $character (@ra_valCharacters)
         {
             if ($character =~ /[\w-]/)
             {
                 $seperatorBetweenSyntax.=$character;
             }
             elsif ($character =~ /([\\\/:*?"<>|])/) # patterns not supported by windows
             {
                 die ("ERROR: Config file section $section parameter $parameter contains unsupported character $1 for file/folder naming. \n Unsupported characters: \\ / : * ? \" < > | \n");
             }
             else
             {
                 ## For characters like .,$,%,^,so on ex: \., \$
                 $seperatorBetweenSyntax.='\\'.$character;
             }
          }
     }
     
    return ($syntax,$seperatorBetweenSyntax);
}

#****************************************************************************
# Public subfunction
#
# Configure folder regex using prefix information from configuration 
# file "FolderPrefix" section
#****************************************************************************
sub folderRegex
 {
    my %args = @_;
    my $configFile;
    my $section="FolderPrefix";
    my $prefixParam = "PRE_SF_FL";
    
    foreach my $argument (keys (%args))
      {
        if ($argument eq 'ConfigFile')
          {
            $configFile = $args{$argument};  
          }
        else
          {
            die ("INTERNAL ERROR: Unknown argument \"$argument\"");
          }
      }

    die ("INTERNAL ERROR: Missing argument \"ConfigFile\"") unless (defined $configFile);
    die ("ERROR: $configFile file does not exists\n") unless (-e $configFile);    
    
    my $checkDirConfigIni = IniFiles->new ( -file => $configFile );
    die ("ERROR: invalid options $configFile : $!") unless ( defined $checkDirConfigIni );
   
    my $folderPrefixSeperator = $checkDirConfigIni->val( $section, "PRE_SEP" );
    die ("Multiple data for folder prefix seperator provided $folderPrefixSeperator\n") if (scalar(split(//,$folderPrefixSeperator)) > 1);
    $folderPrefixSeperator = '\\'.$folderPrefixSeperator;
    
    # PRE_SF_FLn is mandatory and should be available. 
    # To check PRE_SF_FLn availability in config file. If not error will be generated and tool will abort
    $checkDirConfigIni->val( $section, $prefixParam.'n' );
    
    # Folder number to validate if PRE_SF_FL in config file is in sequence order 0,1,2....n
    my $folderNumber=0;
    my $folderLevelSyntax; # To store for processing which folder level regex should be configured
    
    my $dirSearchPattern = '';
    
    foreach my $parameter ( $checkDirConfigIni->Parameters ( $section ) )
      {
        next if ($parameter eq "PRE_SEP");
        
        if($parameter =~ /\A$prefixParam(\d+|n)\Z/)
        {
            $folderLevelSyntax = $1;
            
            if($folderLevelSyntax ne 'n' && $folderLevelSyntax ne $folderNumber)
            {
                die ("\nERROR: Config file section $section has invalid $parameter order\n".
                     "$prefixParam should be incremental order 0 1 .... n\n");
            }
            
            my $value = $checkDirConfigIni->val( $section, $parameter );
            
            # Create array by splitting using config file enclosed syntax <> and 
            # remove any empty spaces generated by default due to splitting
            my @ra_valData =  grep { /\S/ } split(/(<[\w\s]+>)/,$value);
            #warn "$parameter = $value\n";
            
            my $syntax = '';
            foreach my $data (@ra_valData)
             {
               my ($commonSyntax,$seperatorBetweenSyntax) = _commonSyntax($data,$section,$parameter);
               $syntax.=$commonSyntax;
               
               if(defined $seperatorBetweenSyntax){
                   $syntax.=$seperatorBetweenSyntax;
               }
               
             }

            # Store each prefix syntax in hash. 
            # Used by fileRegex to obtain actual subfolder prefixes from scanning folder
            # ex: prefixSubfolderReg = \d{1} , \[a-z]{1}
            # During file regex: InputFolder/0_name/1_22_name/A_55name/33_name...
            # subfolder prefixes will be: 0, 1, A, 33... in sequence order representing each folder level prefix
            $prefixSubfolderReg{$parameter} = $syntax;
            
            $syntax.=$folderPrefixSeperator;
            
            # Ex: PRE_SF_FL0 = <d1>, PRE_SEP = _
            # syntax will be \d{1}\_[\_\w-]+
            $syntax.='['.$folderPrefixSeperator.'\w-]+';
            
            # If PRE_SF_FLn then its end of the regex
            if($folderLevelSyntax eq 'n'){
                
                # If configured PRE_SF_FL for 0 or 1 i.e. 2 subfolders
                # Ex: PRE_SF_FL0 = <d2>, PRE_SF_FLn = <c1>, PRE_SEP = .
                # regex: /\d{2}\.[\.\w-]+(/[a-z]{1})*?     
                if($folderNumber =~ /0|1/)
                 {
                    $dirSearchPattern.='(/'.$syntax.')*?';
                 }
                else
                 {
                   # If configured PRE_SF_FL for more then 2 sub folder
                   # Ex: PRE_SF_FL0 = <d2>, PRE_SF_FL1 = <c1>, PRE_SF_FL2 = <d1>, PRE_SF_FLn = <C1>, PRE_SEP = .
                   # regex: /\d{2}\.[\.\w-]+(/[a-z]{1}\.[\.\w-]+(/\d{1}\.[\.\w-]+(/[A-Z]\.[\.\w-]+)*)?)?
                   my $closingBracket = ')?' x ($folderNumber - 2);
                   $dirSearchPattern.='(/'.$syntax.')*'.$closingBracket.')?';
                 }
            }
            elsif($folderNumber ge 1){
                $dirSearchPattern.='(/'.$syntax.'';
            }
            else{
                $dirSearchPattern.='/'.$syntax;
            }
            
           # warn "\n seachpattern: $dirSearchPattern\n";
            $folderNumber++;
            
         }
        else{
            die ("ERROR: Config file section $section contains invalid parameters $parameter\n")
        }
      } 
        
    my $dirRegex = qr/$dirSearchPattern/;

    return $dirRegex;
 }


#****************************************************************************
# Public subfunction
#
# Configure file regex using File naming information from configuration 
# file "FileName" section
#****************************************************************************
sub fileRegex
 {
    my %args = @_;
    my $configFile;
    my $currentFilePath;
    my $section="FileName";

    foreach my $argument (keys (%args))
      {
        if ($argument eq 'ConfigFile')
          {
            $configFile = $args{$argument};  
          }
        elsif ($argument eq 'currentFilePath')
         {
              $currentFilePath = $args{$argument};
         }
        else
          {
            die ("INTERNAL ERROR: Unknown argument \"$argument\"");
          }
      }

    die ("INTERNAL ERROR: Missing argument \"ConfigFile\"") unless (defined $configFile);
    die ("INTERNAL ERROR: Missing argument \"currentFilePath\"") unless (defined $currentFilePath);
    die ("ERROR: $configFile file does not exists\n") unless (-e $configFile);

    if (keys %prefixSubfolderReg eq 0)
    {
        folderRegex('ConfigFile' => $configFile);
    }
    #warn Dumper \%prefixSubfolderReg;
    
    my $checkDirConfigIni = IniFiles->new ( -file => $configFile );
    die ("ERROR: invalid options $configFile : $!") unless ( defined $checkDirConfigIni );
    
    my $folderPrefixSeperator = $checkDirConfigIni->val( "FolderPrefix", "PRE_SEP" );
    
    # To Obtain subfolder prefixes from current scanning currentFilePath input 
    my $preData = join ('|', map { "($prefixSubfolderReg{$_})" } keys %prefixSubfolderReg);
    $preData = '('.$preData.')\\'.$folderPrefixSeperator;
    
    my $preReg = qr/$preData/;
    my @fileNameBase;

    # ex: prefixSubfolderReg = \d{1} , \[a-z]{1}
    # During file regex: InputFolder/0_name/1_22_name/A_55name/33_name
    # fileNameBase = (0, 1, A, 33) in sequence order representing each folder level prefix
    while ($currentFilePath =~ m!/$preReg!g)
      {
         push (@fileNameBase, $1);
      }
    
    # Folder level of currentFilePath scanning 
    # Ex: InputFolder/0_name/1_22_name/A_55name/33_name --> folderlevel = 4
    # Ex: InputFolder/0_name/1_22_name --> folderlevel = 2
    my $folderLevel = @fileNameBase; 

    my @ra_fileParameters = $checkDirConfigIni->Parameters ( $section );
    my $parameter = 'FN_FL';
    
    my $invalidParams = join (', ', grep {$_ !~ /\A$parameter(\d+|n)\Z/} @ra_fileParameters);
    die ("ERROR: Config file section $section contains invalid parameters $invalidParams\n") if ($invalidParams ne '');
    
    my $value;
    
    # Configured file name data for specific folder level. Ex: FN_FL2 for folder level 2
    # If not present then FN_FLn will be applicable by default
    if ( grep {/$parameter$folderLevel/} @ra_fileParameters ){
        $parameter.=$folderLevel;
        $value = $checkDirConfigIni->val( $section, $parameter );
    }
    else{
        $parameter.='n';
        $value = $checkDirConfigIni->val( $section, $parameter );
    }

    # warn "\n$parameter = $value\n\n";
    
    # Check if FolderPrefix used in FileName is in incremental order or mentioned multiple times
    # Ex: <ProjectName>_<PRE_SF_FL0><PRE_SF_FL2>_<PRE_SF_FL1>_ --> invalid PRE_SF_FL1 should come before PRE_SF_FL2
    my $previousPreNumber;
    while ($value =~ /<(PRE_SF_FL(\d+|n))>/g)
      {
         if(defined $previousPreNumber && ($previousPreNumber eq 'n')){
             my $orderError = '';
             if($2 eq 'n'){
                 $orderError = "<PRE_SF_FLn> mentioned multiple times for file name";
             }else{
                 $orderError = "<$1> should come before <PRE_SF_FLn>";
             }
             die ("\nERROR: Config file section $section parameter $parameter value has invalid FolderPrefix order\n".
                  "$orderError\n");
         }elsif(defined $previousPreNumber && ($2 ne 'n') && ($2 <= $previousPreNumber)){
             my $orderError = '';
             if ($2 == $previousPreNumber){
                 $orderError = "<PRE_SF_FL$2> mentioned multiple times for file name";
             }else{
                 $orderError = "<$1> should come before <PRE_SF_FL$previousPreNumber>";
             }
             
             die ("\nERROR: Config file section $section parameter $parameter value has invalid FolderPrefix order\n".
                  "$orderError\n");
         }
         $previousPreNumber = $2;
      }
            
    # Create array by splitting using config file enclosed syntax <> and 
    # remove any empty spaces generated by default due to splitting
    my @ra_valData =  grep { /\S/ } split(/(<[\w\s]+>)/,$value);

    my $syntax = '';
    
    # To check and store if previous <PRE_SF_FL> used in current file name
    my $previous_PRE_SF_FolderLevel;
    
    # To store seperator for file name to configure regex using <PRE_SF_FL>
    my $fileNameSeperator;
    
    foreach my $data (@ra_valData)
     {
         my $commonSyntax;
         my $seperatorBetweenSyntax;
         
         if($data =~ '\A<(ProjectName)>\Z')
         {
             my $prjName = $checkDirConfigIni->val( $1, "Name" );
             $syntax.="\Q$prjName\E";
         }
         elsif ($data =~ '<PRE_SF_FL(\d+|n)>')
         {
             # Critical configuration
             if( defined $previous_PRE_SF_FolderLevel && $1 eq 'n'){
                 if(@fileNameBase ne 0){
                     my $sepForPrefix = '';
                     $sepForPrefix = $fileNameSeperator if (defined $fileNameSeperator);
                     $syntax .= join ($sepForPrefix, @fileNameBase);
                 }
                 elsif(defined $fileNameSeperator){
                     $syntax =~ s/(.*)\Q$fileNameSeperator\E$/$1/;
                 }
             }
             elsif( defined $previous_PRE_SF_FolderLevel ){
                my $sepForPrefix = '';
                for ( my $i=$previous_PRE_SF_FolderLevel; $i<=$1-1; $i++ ){
                     if(@fileNameBase ne 0){
                         $syntax.=$sepForPrefix;
                         $syntax.=shift(@fileNameBase);
                         $sepForPrefix = $fileNameSeperator if (defined $fileNameSeperator);
                     }
                     elsif(defined $fileNameSeperator){ 
                       # To remove previous file seperator
                       # Ex: regex needs to be build using <ProjectName>_<PRE_SF_FL0>_<PRE_SF_FL1>_<PRE_SF_FLn>_<d3>_<filename>.<ext>
                       # But fileNameBase has no data for PRE_SF_FL1.
                       #
                       # Input folder: InputFolder/0_name, only 0th folder , ProjectName = AB15
                       # Till here regex will be configured : AB15_0_
                       # For 0th folder level PRE_SF_FL1 is not there so further configuration will be done as:
                       # AB15_0_<PRE_SF_FL1>_<PRE_SF_FLn>_<d3>_<filename>.<ext> will result in 
                       # AB15_0__<PRE_SF_FLn>_<d3>_<filename>.<ext>, where extra _ (i.e. current fileNameSeperator) is from _<PRE_SF_FL1>
                       # 
                       # Hence with below replacement operation fileNameSeperator "_" before <PRE_SF_FL1> will be removed
                       # Now regex till here after replacement will be "AB15_0" instead of "AB15_0_"
                       # And _<PRE_SF_FLn> replacement will happen in first if condition of PRE_SF_FLn checking
                       $syntax =~ s/(.*)\Q$fileNameSeperator\E$/$1/;
                     }
                 }
             }
             else{
                 my $sepForPrefix = '';
                 for ( my $i=0; $i<=$1; $i++ ){
                     if(@fileNameBase ne 0){
                        $syntax.=$sepForPrefix;
                        $syntax.=shift(@fileNameBase);
                        $sepForPrefix = $fileNameSeperator if (defined $fileNameSeperator);
                     }
                     elsif(defined $fileNameSeperator){
                        $syntax =~ s/(.*)\Q$fileNameSeperator\E$/$1/;
                    }
                 }
             }

             $previous_PRE_SF_FolderLevel = $1;
         }
         elsif ($data =~ '<filename>')
         {
             $syntax.='([\w-]+)(_V(\d)+\.(\d)+)?';
         }
         elsif ($data =~ '<ext>')
         {
             $syntax.='(\w+)$';
         }
         else
         {
             ($commonSyntax,$seperatorBetweenSyntax) = _commonSyntax($data,$section,$parameter);
             $syntax.=$commonSyntax;
         }
         
         if(defined $seperatorBetweenSyntax){
            $syntax.=$seperatorBetweenSyntax;
            $fileNameSeperator = $seperatorBetweenSyntax;
         }else{
            $fileNameSeperator = undef;
         }
     }
     my $fileRegex = qr/$syntax/;
     # warn "syntax: $fileRegex\n\n";

     return $fileRegex;
 }
 
 
#****************************************************************************
# Public subfunction
# 
# Return list of whiteList file Patterns from configuration file
# "WhiteList" section
#****************************************************************************
 sub getWhiteList {
	my %args = @_;
    my $configFile;
    my $section="WhiteList";
	my @WhiteList = ();
	foreach my $argument (keys (%args)) {
        if ($argument eq 'ConfigFile') {
			$configFile = $args{$argument}; 
        } else {
            die ("INTERNAL ERROR: Unknown argument \"$argument\"");
        }
    }

    die ("INTERNAL ERROR: Missing argument \"ConfigFile\"") unless (defined $configFile);
    die ("ERROR: $configFile file does not exists\n") unless (-e $configFile);
	my $checkDirConfigIni = IniFiles->new ( -file => $configFile );
	die ("ERROR: invalid options $configFile : $!") unless ( defined $checkDirConfigIni );
   
    my @ra_fileParameters = $checkDirConfigIni->Parameters($section);
    my $parameter = 'WL_PTRN';
    
    my $invalidParams = join (', ', grep {$_ !~ /\A$parameter(\d+)\Z/} @ra_fileParameters);
    die ("ERROR: Config file section $section contains invalid parameters $invalidParams\n") if ($invalidParams ne '');

    foreach my $parameter (keys %{$checkDirConfigIni->{sections}->{$section}->{parameters}}) {
		my $value = $checkDirConfigIni->{sections}->{$section}->{parameters}->{$parameter}->{value};
		my $pattern;
		$value =~ s!\\!/!g;  
		my @data  = split '/', $value;

		my $cnt = 0;
		while ($cnt < @data) {
			if ($cnt < $#data) {
				if ($data[$cnt] =~ m/\*/g) {
					$pattern .= '.*/';	
				} else {
					$pattern .= $data[$cnt].'/';
				}				
			} else {
				if ($data[$cnt] =~ m/^\*\.(\w+)$/g) {
					$pattern .= '.*\.'.$1;
				} 
				elsif ($data[$cnt] =~ m/^[\w_]+$/g) {
					$pattern .= $data[$cnt].'[/.*]?';
				}
				elsif ($data[$cnt] =~ m/^\*(\.\*)?$/g) {
					$pattern .= '.*';
				}
				else { 
					$pattern .= $data[$cnt];
				}
			}
			$cnt++;
		}
		push @WhiteList, $pattern if defined $pattern;
	}
	
	return @WhiteList;
 }

1;