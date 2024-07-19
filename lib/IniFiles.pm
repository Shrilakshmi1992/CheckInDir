package IniFiles;

use strict;
use warnings;


=head1 IniFiles

=head1 Why/what

The package provides the content of an ini file: Sections and Parameters.

=cut


=head2 new

B<Classification:Public>

This method creates and returns a new IniFile object.

Usage:

  <Object> = IniFiles->new ();

Returns:

  a new IniFiles object

=cut

my @requiredSections = ("ProjectName","FolderPrefix","FileName","SeparateFolder","WhiteList");

sub new
  {
    # start of argument passing
    my @arguments = @_;
    my $classname = shift @arguments;
    my %args = @arguments;

    my $self = {};
    bless( $self, $classname );

    my %sections = ();
    $self->{sections} = \%sections;
    $self->{errors} = 0;

    foreach my $argument ( keys %args )
      {
        if ( $argument eq '-file' )
          {
            $self->{fileName} = $args{$argument};
          }
        else
          {
            die ("INTERNAL ERROR: Unknown argument \"$argument\"");
          }
      }
    # end of argument passing
    
    die ("INTERNAL ERROR: Missing argument \"-file\"") unless (defined $self->{fileName});

    $self->ReadConfig() if (-e $self->{fileName});
    
    my $sectionsStr = join (', ', map { "[$_]" } @requiredSections);
    my $actualSectionCount = $self->Sections();
    
    die ("ERROR: Invalid $self->{fileName} file. Required sections $sectionsStr are missing\n") 
            if (@requiredSections ne $actualSectionCount);
    
    return $self;
  }

=head2 val

Returns the value of the given parameter of the given section.

=cut

sub val
  {
    # start of argument passing
    my @arguments = @_;
    my $self = shift @arguments;
    my $sectionName = shift @arguments;
    my $parameterName = shift @arguments;
    # end of argument passing

    if (not exists $self->{sections}{$sectionName})
      {
         die ("INTERNAL ERROR: Trying to access Section $sectionName which does not exists\n");
      }
    
    if (exists $self->{sections}{$sectionName}{parameters}{$parameterName})
      {
        return $self->{sections}{$sectionName}{parameters}{$parameterName}{value};
      }
    else
      {
        die ("ERROR: Invalid $self->{fileName} file. Parameter $parameterName is missing from section $sectionName \n");
      }
  }


=head2 newval

Assignes a new value to the given parameter in the given section
file.

=cut

sub newval
  {
    # start of argument passing
    my @arguments = @_;
    my $self = shift @arguments;
    my $sectionName = shift @arguments;
    my $parameterName = shift @arguments;
    my $value = shift @arguments;
    # end of argument passing

    $self->AddSection($sectionName) unless (exists $self->{sections}{$sectionName});
    
     if (exists $self->{sections}{$sectionName}{parameters}{$parameterName})
      {
        die ("ERROR: Invalid $self->{fileName} file. $parameterName available multiple times in $sectionName section\n");
      }
      else
      {
          $self->{sections}{$sectionName}{parameters}{$parameterName}{sortNumber} = keys %{$self->{sections}{$sectionName}{parameters}};
      }
    $self->{sections}{$sectionName}{parameters}{$parameterName}{value} = $value;

    return;
  }


=head2 ReadConfig

Reads the ini file line-by-line.

=cut

sub ReadConfig
  {
    # start of argument passing
    my @arguments = @_;
    my $self = shift @arguments;
    # end of argument passing

    my $lineCounter = 0;
    my $currentSection = '';
    open (my $fhIN, '<', $self->{fileName}) or die("ERROR: Cannot read $self->{fileName}: $!");
    while (<$fhIN>)
      {
        $self->_readLine('lineCounter' => \$lineCounter, 'line' => $_, 'currentSection' => \$currentSection);
      }
    close $fhIN;

    if ($self->{errors} > 0)
      {
        die ("ERROR: syntax errors found in $self->{fileName}\n");
      }
    return;
  }

sub _readLine
  {
    # start of argument passing
    my @arguments = @_;
    my $self = shift @arguments;
    my %args = @arguments;

    my $rs_lineCounter;
    my $line;
    my $rs_currentSection;

    foreach my $argument ( keys %args )
      {
        if ( $argument eq 'lineCounter' )
          {
            $rs_lineCounter = $args{$argument};
          }
        elsif ( $argument eq 'line' )
          {
            $line = $args{$argument};
          }
        elsif ( $argument eq 'currentSection' )
          {
            $rs_currentSection = $args{$argument};
          }
        else
          {
            die ("INTERNAL ERROR: Unknown argument \"$argument\"");
          }
      }
    # end of argument passing
    die ("INTERNAL ERROR: Missing argument \"lineCounter\"") unless defined $rs_lineCounter;
    die ("INTERNAL ERROR: Missing argument \"line\"") unless defined $line;   
    die ("INTERNAL ERROR: Missing argument \"currentSection\"") unless defined $rs_currentSection;

    $$rs_lineCounter++;
    if ($line =~ /^\s*\[\s*(.+?)\s*\]\s*$/ )
      {
        $$rs_currentSection = $1;
        $self->AddSection($$rs_currentSection);
      }
    elsif ($line =~ /^\s*([^=]+?)\s*=\s*(.*?)\s*$/)
      {
        my $name  = $1;
        my $value = $2;

        if ($value ne '' || $name eq "SEP_FLDR")
         {
           if($value =~ /\s/ && $name ne "SEP_FLDR"){
             warn "ERROR: Value of Parameter $name of section $$rs_currentSection contains space in $line ($self->{fileName}:$$rs_lineCounter)\n";  
             $self->{errors}++;             
           }else{
               $self->newval($$rs_currentSection,$name,$value);
           }
         }
        else
         {
           warn "ERROR: Value missing for Parameter $name of section $$rs_currentSection in $line ($self->{fileName}:$$rs_lineCounter)\n";
           $self->{errors}++;           
         }
      }
    elsif ($line =~ /^\s*(?:\#|\;|$)/) # comments and empty lines.
      {
        # ignore
      }
    else
      {
        warn "ERROR: Syntax error in $line ($self->{fileName}:$$rs_lineCounter)\n";
        $self->{errors}++;
      }
    return;
  }

=head2 Sections

Returns an array containing section names.

=cut

sub Sections
  {
    # start of argument passing
    my @arguments = @_;
    my $self = shift @arguments;
    # end of argument passing
    my @sectionNames = ();
    foreach my $sectionName (sort {$self->{sections}{$a}{sortNumber} <=> $self->{sections}{$b}{sortNumber}} keys %{$self->{sections}})
      {
        push @sectionNames, $sectionName;
      }
    return @sectionNames;
  }

=head2 AddSection

Adds a section to the existing Ini file. If the section already exists, do nothing.

=cut

sub AddSection
  {
    # start of argument passing
    my @arguments = @_;
    my $self = shift @arguments;
    my $sectionName = shift @arguments;
    # end of argument passing
    
    my $sectionsStr = join (', ', map { "[$_]" } @requiredSections);
    die "ERROR: Invalid Section '$sectionName' found in $self->{fileName} file. Only $sectionsStr are allowed\n"
           unless ( grep {/^\Q$sectionName\E$/} @requiredSections );
    
    unless (exists $self->{sections}{$sectionName})
      {
        $self->{sections}{$sectionName}{sortNumber} = keys %{$self->{sections}};
        my %parameters = ();
        $self->{sections}{$sectionName}{parameters} = \%parameters;
      }
    return;
  }

=head2 Parameters

Returns an array containing the parameters contained in the given section.

=cut

sub Parameters
  {
    # start of argument passing
    my @arguments = @_;
    my $self = shift @arguments;
    my $sectionName = shift @arguments;
    # end of argument passing

    my @parameterNames = ();

    if (exists $self->{sections}{$sectionName})
      {
        my $rh_parameters = $self->{sections}{$sectionName}{parameters};
        foreach my $parameterName (sort {$rh_parameters->{$a}{sortNumber} <=> $rh_parameters->{$b}{sortNumber}} keys %$rh_parameters)
          {
            push @parameterNames, $parameterName;
          }
      }
    return @parameterNames;
  }

=head2 WriteConfig

Writes the ini file.

=cut

sub WriteConfig
  {
    # start of argument passing
    my @arguments = @_;
    my $self = shift @arguments;
    my $fileName = shift @arguments;
    # end of argument passing

    $self->{fileName} = $fileName if (defined $fileName);
    my $content = '';
    foreach my $sectionName ($self->Sections())
      {
        $content .= '[' . $sectionName .']'."\n";
        foreach my $parameterName ($self->Parameters($sectionName))
          {
            $content .= "$parameterName=".$self->val($sectionName,$parameterName)."\n";
          }
        $content .= "\n";
      }
    open (my $fhOUT, '>', $self->{fileName}) or die("Cannot write $self->{fileName}: $!");
    print $fhOUT $content;
    close $fhOUT;
    return;
  }

=head2 SetFileName

Sets the filename of the ini file.

=cut

sub SetFileName
  {
    # start of argument passing
    my @arguments = @_;
    my $self = shift @arguments;
    my $fileName = shift @arguments;
    # end of argument passing

    $self->{fileName} = $fileName;
    return;
  }

1;
