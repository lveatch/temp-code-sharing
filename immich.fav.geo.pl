#!/usr/bin/perl

use Immich::API;
use Getopt::Long;
use File::Copy;
use Data::Dumper;
use Geo::Point;
use File::Find;


my $address = '';
my $where = '';
my $map = '';   # google maps copy / paste long,lat
my $copyFrom = '';  # copy from file
my $test;
my $force;
my $verbose;
my $xmp;
my $removeFavorite = 1; # --no-remove

my $result = GetOptions (
                         "address:s"   => \$address,
                         "where:s"     => \$where,
                         "map:s"       => \$map,
                         "copy:s"      => \$copyFrom,
                         "force"       => \$force,
                         "test"        => \$test,
                         "verbose"     => \$verbose,
                         "xmp"         => \$xmp,
                         "remove!"     => \$removeFavorite,
                        );

my %where2gps = (

                );

unless ($where eq '') {
    $address = $where2gps{lc $where};
    if ($address =~ m/^map:(.+$)/) {
        $map = $1;
        $address = '';
    } elsif ($address =~ m/^copyfrom:(.+$)/) {
        $copyFrom = $1;
        $address = '';
    }
    
}


unless ($address eq '') {
    print "address = $address ....\n";
    our ($latitude, $longitude) = zipCodeLookup($address);
    $map = "$latitude,$longitude";
}



if ($copyFrom eq '') {
   if ($map eq '') {
       print "\n-where and -map cannot both be blank\n\n";
       exit 1;
   }

   our ($lat, $lon) = split(/,/, $map);
   print "lat = $lat, lon = $lon\n";

   if ($lat eq '' or $lon eq '') {
     print "\nlat and/or lon can not be blank.\nexiting.\n\n";
     exit 1;
   }
}


my $immich = Immich::API->new( {
        server  => 'https://photo.******',
        apiKey  => '******',
        #debug   => 1,
    }
);


my $totalAssets = 0;
my @assets;

my $requestJson  = qq({);
   $requestJson .= qq( "isFavorite" : "true" );
   $requestJson .= qq(});

$immich->searchAssets($requestJson, \@assets, \$totalAssets);
#print  Dumper(@assets);
#exit 9;

our %seen;
my $updateCounter = 0;
foreach my $key (@assets) {
    my $file         = $key->{'originalPath'};
    my $originalPath = $key->{'originalPath'};
    my $filename     = $key->{'originalFileName'};
    my $assetId      = $key->{'id'};
    $updateCounter++;

    if ($copyFrom eq '') {
       print "\nprocessing (1) $file ($updateCounter of $totalAssets) ....\n";
       exifTool($lon, $lat, $file);
    
       if ($file =~ m#^/mnt/plexphotos/camera_images/#i) {
           $file =~ s#^/mnt/plexphotos/camera_images/#/mnt/camera_images/#;
           print "processing (2) $file  ($updateCounter of $totalAssets) ....\n";
           exifTool($lon, $lat, $file);
       } elsif ($file =~ m#^/mnt/plexphotos/#i) {
           $file =~ s#^/mnt/plexphotos/#/mnt/camera_images/mobile backups/#;
           print "finding $file  ($updateCounter of $totalAssets) ....\n";
           our $fileLocation = '';
           findManualFile($file, $filename, $originalPath);
           print qq(\tfile location is $fileLocation\n);
           exifTool($lon, $lat, $fileLocation);
       }

       # remove asset from immich's Favorites
       unless ($test) {
          if ($removeFavorite) {
             my $rc = $immich->unfavoriteAsset($assetId);
             if ($rc eq 1) {
                print "   -=-=- asset $filename removed from favorites.\n";
             } else {
                print "   -=-=- asset $filename was not removed from favorites.\n";
             }
          }
       }


    } elsif ($copyFrom ne '') {
       print "\nprocessing tags (4) $file ($updateCounter of $totalAssets) ....\n";
       exifToolTagsfromfile($copyFrom, $file);
    
       if ($file =~ m#^/mnt/plexphotos/camera_images/#i) {
           $file =~ s#^/mnt/plexphotos/camera_images/#/mnt/camera_images/#;
           print "processing tags (5) $file  ($updateCounter of $totalAssets) ....\n";
           exifToolTagsfromfile($copyFrom, $file);
       } elsif ($file =~ m#^/mnt/plexphotos/#i) {
           #$file =~ s#^/mnt/plexphotos/#/mnt/camera_images/mobile backups/manual/#;
           $file =~ s#^/mnt/plexphotos/#/mnt/camera_images/mobile backups/#;
           print "processing tags (6) $file  ($updateCounter of $totalAssets) ....\n";
           our $fileLocation = '';
           findManualFile($file, $filename, $originalPath);
           print qq(\tfile location is $fileLocation\n);
           exifToolTagsfromfile($copyFrom, $fileLocation) unless ($fileLocation eq '');
       }

       # remove asset from immich's Favorites
       unless ($test) {
          if ($removeFavorite) {
             my $rc = $immich->unfavoriteAsset($assetId);
             if ($rc eq 1) {
                print "   -=-=- asset $filename removed from favorites.\n";
             } else {
                print "   -=-=- asset $filename was not removed from favorites.\n";
             }
          }
       }

    }
   
 
    unless ($test) {
       # export jpg to xmp sidecar file for immich metadata refresh
       writeSidecarFile($originalPath, "${originalPath}.xmp");
      
       print "\nrefreshing metadata for $assetId ...\n"; 
       $immich->refreshMetadata($assetId);
       print " ... done\n"; 

    }

}


unless ($test) {
   print "\n\nmoving on to extracting immich data to xmp sidecar files .....\n";
   monitorJobs();

   foreach my $key (@assets) {
      my $file         = $key->{'originalPath'};
      my $originalPath = $key->{'originalPath'};
      my $filename     = $key->{'originalFileName'};
      my $assetId      = $key->{'id'};
      $xmpCounter++;
  
      my $verboseOption = ($verbose) ? '-v' : '';
      print "\nexporting xmp sidecar file(s) [$filename, $assetId, $originalPath]   ($xmpCounter of $totalAssets)";
      print qx(perl export.asset.info.2.xmp.pl -image "$originalPath" -force $verboseOption);
   
   }

   print "    .....done.\n\n";
}


exit 0;



sub exifTool
{
    my ($gpsLong, $gpsLat, $pic) = @_;

#   exiftool -overwrite_original -preserve    -XMP:GPSLongitude="$2"   -XMP:GPSLatitude="$1"  -GPSLongitudeRef="West" -GPSLatitudeRef="North" $3
#   exiftool -overwrite_original -preserve   -EXIF:GPSLongitude="$2"  -EXIF:GPSLatitude="$1"  -GPSLongitudeRef="West" -GPSLatitudeRef="North" $3

    #print "$gpsLong, $gpsLat, $pic\n";

    if ($test) {    
        (my $tmpFile = $pic) =~ s#/#_#g;
        $tmpFile = "/mnt/ramd/$tmpFile";
        copy($pic, $tmpFile);
        $pic = $tmpFile;
        print "----------------- test -----------> $gpsLong, $gpsLat, $pic\n";
    }


    unless ($force) {
        my $commandCheck  = "exiftool -'GPSPosition'   ";
           $commandCheck .= "'$pic' ";
        open (CHECK, " $commandCheck |")
                or die "Cannot open exiftool XMP command, $!";
    
        while (my $line = <CHECK>) {
          if ($line =~ m/gps position/i) {
            close CHECK;
            print "\t skipping GPS update as pre-exists\n";
            return;
          }
        }
        close CHECK;
    }


    
    my $command  = "exiftool -overwrite_original -preserve   ";
       $command .= "-XMP:GPSLongitude='$gpsLong'   ";
       $command .= "-XMP:GPSLatitude='$gpsLat' ";
       $command .= "-EXIF:GPSLongitude='$gpsLong'   ";
       $command .= "-EXIF:GPSLatitude='$gpsLat'  ";
       my $longRef = ($gpsLong < 0) ? 'West' : 'East';
       $command .= "-GPSLongitudeRef='$longRef' ";
       my $latRef = ($gpsLat < 0) ? 'South' : 'North';
       $command .= "-GPSLatitudeRef='$latRef'  ";
       $command .= "'$pic' ";
       
    if ($test) {
        print "$command\n";
        return;
    }

    open (OUTPUT, " $command |")
            or die "Cannot open exiftool XMP command, $!";

    
    while (my $line = <OUTPUT>) {
      print $line;
    }
    close OUTPUT;


    
}



sub exifToolTagsfromfile
{
    my ($source, $target) = @_;

    if ($test) {    
        (my $tmpFile = $target) =~ s#/#_#g;
        $tmpFile = "/mnt/ramd/$tmpFile";
        copy($target, $tmpFile);
        $target = $tmpFile;
        print "----------------- test -----------> $source, $target\n";
    }

    unless ($force) {
        my $commandCheck  = "exiftool -'GPSPosition'   ";
           $commandCheck .= "'$target' ";
        open (CHECK, " $commandCheck |")
                or die "Cannot open exiftool XMP command, $!";
    
        while (my $line = <CHECK>) {
          if ($line =~ m/gps position/i) {
            close CHECK;
            print "\t skipping GPS update as pre-exists\n";
            return;
          }
        }
        close CHECK;
    }


    
    my $command  = "exiftool -overwrite_original -preserve -tagsfromfile  ";
       $command .= "'$source' ";
       $command .= '-gps:all ';
       $command .= "'$target' ";
       
    #if ($test) {
    #    print "$command\n";
    #    return;
    #}

    open (OUTPUT, " $command |")
            or die "Cannot open exiftool gps copy command, $!";

    
    while (my $line = <OUTPUT>) {
      print $line;
    }
    close OUTPUT;

}




sub writeSidecarFile
{
    my ($source, $target) = @_;

    if ($test) {
        (my $tmpFile = $target) =~ s#/#_#g;
        $tmpFile = "/mnt/ramd/$tmpFile";
        copy($target, $tmpFile);
        $target = $tmpFile;
        print "----------------- test -----------> $source, $target\n";
    }

    my $command  = "exiftool -overwrite_original -tagsfromfile ";
       $command .= "'$source' ";
       $command .= '-@ /usr/share/libimage-exiftool-perl/exif2xmp.args ';
       $command .= '-@ /usr/share/libimage-exiftool-perl/iptc2xmp.args ';
       $command .= '-all:all ';
       $command .= "'$target' ";

    open (OUTPUT, " $command |")
            or die "Cannot open exiftool gps copy command, $!";


    while (my $line = <OUTPUT>) {
      print $line;
    }
    close OUTPUT;

    if ($verbose) {
       print qq(writeSidecarFile of $source, $target\n";);
       print qx(cat $target);
    }

}




sub zipCodeLookup
{
    my ($address) = @_;

    my $zipTemp;

    #my $raw_url  = "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress?address=$address&benchmark=4&format=json";
    my $raw_url  = "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress?address=$address&benchmark=8&format=json";
    my $url = URI::Heuristic::uf_urlstr($raw_url);

    my $ua = LWP::UserAgent->new();
    $ua->agent('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/65.0.3325.181 Safari/537.36');
    #$ua->agent('User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/65.0.3325.181 Safari/537.36');

    $request = HTTP::Request->new(GET => $url);
    $request->referer('https://geocoding.geo.census.gov/geocoder/geographies/onelineaddress?form');
    #print "request = $request\n";

    my $webRequest = $ua->request($request);
    #print "web request = $webRequest\n";
    #print Dumper($webRequest);

    if ($webRequest->is_success) {
        $webHtml =  $webRequest->decoded_content;  # or whatever
        my $json = JSON->new->allow_nonref;
        $zipTemp = $json->decode( $webHtml );
    }
    else {
        print "error calling $raw_url\n";
        die $webRequest->status_line;
    }

    #print Dumper($zipTemp);

    print qq(Matched on $zipTemp->{result}->{addressMatches}[0]->{matchedAddress}\n) if ($verbose);
    print qq(Using latitude of $zipTemp->{result}->{addressMatches}[0]->{coordinates}->{y}, and longitude of $zipTemp->{result}->{addressMatches}[0]->{coordinates}->{x}\n) if ($verbose);

    return ($zipTemp->{result}->{addressMatches}[0]->{coordinates}->{y}, $zipTemp->{result}->{addressMatches}[0]->{coordinates}->{x});

}




sub findManualFile
{
   our ($file, $filename, $source) = @_;
   
   print 'keys in seen is ' . keys(%seen) . "\n" if ($test);
  
   my $sourceLocation = '';
   if (-e "$source.source") {
      open (Source, '<', "$source.source") or warn qq(cannot open "$source.source" for read, $E\n);
      my @lines = <Source>;
      close Source;
      ($sourceLocation = $lines[0]) =~ s#^/volume1/#/mnt/#;

      print qq(source line is $sourceLocation\n) if ($test);
      $fileLocation = $sourceLocation;
      return;
   } 
   
   #my $origionalFilePath = '/mnt/camera_images/mobile backups/manual';
   my $origionalFilePath = '/mnt/camera_images/mobile backups';

   if ($file =~ m#/mnt/camera_images/mobile backups/(.+?)/#i) {
      my $phoneName = $1;
      $phoneName = 'phone' if ($phoneName eq 'len');
      $origionalFilePath .= "/$phoneName";
      print "\t\tsearch root is now $origionalFilePath\n";
   }

   my @searchDir = ($origionalFilePath);
   
   if (defined $seen{$filename}) {
      #print qq(seen $filename\n);
      $fileLocation = $seen{$filename};
      return;
   }
   
   print "\tsearching for $filename at $origionalFilePath .... \n";
   find(\&wanted, @searchDir);

   #print 'keys now seen is ' . keys(%seen) . "\n";

}



sub monitorJobs
{

    my $immichAdmin = Immich::API->new( {
           server  => 'https://photo.*****',
           apiKey  => '******',
           #debug   => 1,
       }
    );


    my $url = 'https://photo.****/api/jobs';

    print "monitoring metadata extraction scan jobs ....\n";
    #print "    pausing 10s to ensure jobs are running.\n";
    #sleep 10;

    my $jobsDone = '';

    until ( $jobsDone eq 'y' ) {
        #sleep 10;

         %jobs;
         $immichAdmin->getJobs(\%jobs);
         #print Dumper(%jobs);
         #print Dumper($jobs{'metadataExtraction'});

         if ($jobs{'metadataExtraction'}->{'jobCounts'}->{'active'} == 0
                 && $jobs{'metadataExtraction'}->{'jobCounts'}->{'waiting'} == 0) {
             $jobsDone = 'y';
             print "metadataExtraction job status:\n";
             print "      jobs: $jobs{'metadataExtraction'}->{'jobCounts'}->{'active'}\n";
             print "   waiting: $jobs{'metadataExtraction'}->{'jobCounts'}->{'waiting'}\n";
         } else {
             $jobsDone = 'n';
             print "metadataExtraction job status:\n";
             print "      jobs: $jobs{'metadataExtraction'}->{'jobCounts'}->{'active'}\n";
             print "   waiting: $jobs{'metadataExtraction'}->{'jobCounts'}->{'waiting'}\n";
         }


    }

    print "..... done.\n";

}




sub wanted
{

   next if ($File::Find::dir =~ m/eaDir/);
   next unless (-f $File::Find::name);
   $name = $_;
   #print "\tfile $File::Find::name and $name\n";
   #print "\t\t$file, $filename\n";
   
   $seen{$name} = $File::Find::name;
   
   if ($name eq $filename) {
      #print 'keys pre seen is ' . keys(%seen) . "\n";
      #print qq(found matching at $File::Find::dir\n);
      print "\tfile $name found at $File::Find::name\n" if ($test);
      #print "\t\t$file, $filename\n";
      $fileLocation = $File::Find::name;
      return;
      
   }

   
}




