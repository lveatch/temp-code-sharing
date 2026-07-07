package Immich::API;

my $VERSION = '0.2';

@ISA = qw/Exporter/;
@EXPORT = qw/searchAssets refreshMetadata unfavoriteAsset unarchiveAsset getAlbumId deleteAlbum createAlbum addAssetToAlbum getLibraryId
                scanLibrary getJobs getDuplicateAssets getAlbumInfo deleteAssetFromAlbum getAssetId getAssetInfo
                getAllPeople updatePerson
                getAllTags
               /;

use strict;
use LWP::UserAgent;
use HTTP::Request;
use URI::Heuristic;
use JSON;
use JSON::MaybeXS qw(encode_json);
use Sys::Hostname;
use Data::Dumper;
#use Geo::Point;


=head1 NAME

Immich::API - Wrapper script allowing calling of Immich's openapi's

=head1 SYNOPSIS

    use Immich::API;
    my $requestJson; #immich formatted json request message.
    my @results_ref; # array reference containing returned results.
    my $total = 0;	# total assets returned.

    my $immich = Immich::API->new(
        {
            server  => 'https://localhost',
            apiKey  => 'secret',
        }
    );

    $immich->searchAssets($requestJson, \@results_ref, \$total);




=head1 DESCRIPTION

Provides central location to call Immich API's


=head1 METHODS

=head2 new($params)


 my $immich = Immich::API->new( {
            server  => 'https://immich.domain.tld',
            port    => 443,
            apiKey  => 'secret',
            userAgent   => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/65.0.3325.181 Safari/537.36''
            debug   => 1,
        }
    );



=cut

sub new {
    my ($class, $params) = @_;

    #return (undef) if (!defined $params->{server});

    my $self = {
        _server => $params->{server} || 'http://localhost',
        _port   => $params->{port} || '',
        _apiKey => $params->{apiKey} || '',
        _debug  => $params->{debug} || 0,
        _userAgent  => $params->{userAgent} || 'Perl - ' . hostname,
    };

    bless $self, $class;


    return ($self);
}


=head2 debug_mode

Sets Debug mode

    $immich->debug_mode(1);


=cut
sub debug_mode {
    my ($self, $mode) = @_;

    $self->{_debug} = $mode;

    return ($self->{_debug});
}



=head2 searchAssets

Returns the found assets to a array reference.

    my $totalAssets = 0;
    my @assets;
    $immich->searchAssets($jsonMessage, \@result, \$totalAssets);

=cut


sub searchAssets
{
    my ($self, $requestIn, $asset_ref, $total) = @_;

    if ($requestIn =~ m/"page".+:.+\d+/i) {
        searchAssetsPage($self, $requestIn, $asset_ref, $total);
        return;
    }
    
    my $webHtml;
    my $urlPort = ($self->{_port} eq '') ? '' : ":$self->{_port}";
    my $url  = "$self->{_server}$urlPort";
       $url .= '/api/search/metadata';
    my $nextPage = 1;


    until ($nextPage eq undef) {
        my $jsonMessage  = $requestIn;
        my $lastRightSquiggleIndex = rindex($jsonMessage, '}');
        my $extraJson = qq(, "page"       : $nextPage );
        substr($jsonMessage, $lastRightSquiggleIndex, 0) = $extraJson;

        print "search JSON = $jsonMessage\n" if ($self->{_debug});

        my $ua = LWP::UserAgent->new();
    	$ua->agent( '$self->{_userAgent}' );
        my $request = HTTP::Request->new(POST => $url);
        $request->content_type('application/json');
        $request->header( 'x-api-key' => $self->{_apiKey} );
    	$request->content($jsonMessage);
    	#print "request = $jsonMessage\n" if ($self->{_debug});

        my $webRequest = $ua->request($request);
        #print "web request = $webRequest\n";
        #print Dumper($webRequest);

        if ($webRequest->is_success) {
            $webHtml =  $webRequest->decoded_content;  # or whatever
        } else {
            warn $url;
            warn $jsonMessage;
            die $webRequest->status_line;
        }

        my $json = JSON->new->allow_nonref;
        my $jsonText = $json->decode($webHtml);

    	if ($self->{_debug}) {
           print "jsonText follows:\n";
           print Dumper($jsonText);
           #exit 1;
    	}

        $nextPage = $jsonText->{'assets'}->{'nextPage'};
        #print "next page = $nextPage\n";
        #print "total items = $jsonText->{'assets'}->{'total'}\n";
        $$total += $jsonText->{'assets'}->{'total'};

        #push @{$asset_ref}, $jsonText->{'assets'}->{'items'}[0];
        push @{$asset_ref}, @{$jsonText->{'assets'}->{'items'}};
        #print Dumper($asset_ref);
        #exit 9;


    }

}


# called from searchAssets if requested json message contains a page : # attribute
sub searchAssetsPage
{
    my ($self, $requestIn, $asset_ref, $total) = @_;

    my $webHtml;
    my $urlPort = ($self->{_port} eq '') ? '' : ":$self->{_port}";
    my $url  = "$self->{_server}$urlPort";
       $url .= '/api/search/metadata';

       
    my $jsonMessage  = $requestIn;
    print "search JSON = $jsonMessage\n" if ($self->{_debug});

    my $ua = LWP::UserAgent->new();
    $ua->agent( '$self->{_userAgent}' );
    my $request = HTTP::Request->new(POST => $url);
    $request->content_type('application/json');
    $request->header( 'x-api-key' => $self->{_apiKey} );
    $request->content($jsonMessage);
    #print "request = $jsonMessage\n" if ($self->{_debug});

    my $webRequest = $ua->request($request);
    #print "web request = $webRequest\n";
    #print Dumper($webRequest);

    if ($webRequest->is_success) {
        $webHtml =  $webRequest->decoded_content;  # or whatever
    } else {
        warn $url;
        warn $jsonMessage;
        die $webRequest->status_line;
    }

    my $json = JSON->new->allow_nonref;
    my $jsonText = $json->decode($webHtml);

    if ($self->{_debug}) {
       print "jsonText follows:\n";
       print Dumper($jsonText);
       #exit 1;
    }

    #print "total items = $jsonText->{'assets'}->{'total'}\n";
    $$total += $jsonText->{'assets'}->{'total'};

    #push @{$asset_ref}, $jsonText->{'assets'}->{'items'}[0];
    push @{$asset_ref}, @{$jsonText->{'assets'}->{'items'}};
    #print Dumper($asset_ref);
    #exit 9;

}




=head2 refershMetadata

Runs a refresh of an assets metadata.


    my $rc = $immich->refreshMetadata($requestJson, $asset_ids);

=cut


sub refreshMetadata
{
    my ($self, $assetIds) = @_;

    my $webHtml;
    my $urlPort = ($self->{_port} eq '') ? '' : ":$self->{_port}";
    my $url  = "$self->{_server}$urlPort";
       $url .= '/api/assets/jobs';

       #my $jsonMessage  = $requestIn;
       #my $lastRightSquiggleIndex = rindex($jsonMessage, '}');
       #my $extraJson = qq(, "name" : "refresh-metadata" );
       #substr($jsonMessage, $lastRightSquiggleIndex, 0) = $extraJson;
    my $jsonMessage  = qq({);
       $jsonMessage .= qq( "assetIds" : [ );
       $jsonMessage .= qq("$assetIds");
       $jsonMessage .= qq( ],);
       $jsonMessage .= qq( "name" : "refresh-metadata" );
       $jsonMessage .= qq(});



    my $ua = LWP::UserAgent->new();
    $ua->agent( '$self->{_userAgent}' );
    my $request = HTTP::Request->new(POST => $url);
    $request->header( 'x-api-key' => $self->{_apiKey} );
    $request->content_type('application/json');
    $request->content($jsonMessage);
    #print "request = $request\n";
    my $webRequest = $ua->request($request);
    #print "web request = $webRequest\n";
    #print Dumper($webRequest);


    if ($webRequest->{'_rc'} == 204) {
        print "refreshed asset $assetIds\n";
        print $webRequest->decoded_content;  # or whatever
    	return 1;
    }
    else {
    	warn $url;
    	warn $jsonMessage;
        warn $webRequest->decoded_content;  # or whatever
        warn $webRequest->status_line;
    	return 0;
    }


}





=head2 unfavoriteAsset

Removes an asset from Favorites.


    my $rc = $immich->unfavoriteAsset($asset_id);

=cut


sub unfavoriteAsset
{
    my ($self, $id) = @_;

    my $webHtml;
    my $urlPort = ($self->{_port} eq '') ? '' : ":$self->{_port}";
    my $url  = "$self->{_server}$urlPort";
       $url .= '/api/assets/';
       $url .= $id;

       #print "$id, $pic, $url\n";

    my $jsonMessage  = qq({);
       $jsonMessage .= qq( "isFavorite": false );
       $jsonMessage .= qq(});


    my $ua = LWP::UserAgent->new();
    $ua->agent( '$self->{_userAgent}' );
    my $request = HTTP::Request->new(PUT => $url);
    $request->header( 'x-api-key' => $self->{_apiKey} );
    $request->content_type('application/json');
    $request->content($jsonMessage);
    my $webRequest = $ua->request($request);


    if ($webRequest->{'_rc'} == 200) {
    	return 1; # success.
    }
    else {
        print "url called is '$url'\n";
        warn $webRequest->decoded_content;  # or whatever
        warn $webRequest->status_line;
    	return 0;
    }



}




=head2 unarchiveAsset

Removes an asset from Favorites.


    my $rc = $immich->unarchiveAsset($asset_id);

=cut


sub unarchiveAsset
{
    my ($self, $id) = @_;

    my $webHtml;
    my $urlPort = ($self->{_port} eq '') ? '' : ":$self->{_port}";
    my $url  = "$self->{_server}$urlPort";
       $url .= '/api/assets/';
       $url .= $id;

       #print "$id, $pic, $url\n";

    my $jsonMessage  = qq({);
       #$jsonMessage .= qq( "isArchived": false );
       $jsonMessage .= qq( "visibility" : "timeline" ); # ?? not sure if this is needed isArchived is now "visibility" : "archive"
       $jsonMessage .= qq(});


    my $ua = LWP::UserAgent->new();
    $ua->agent( '$self->{_userAgent}' );
    my $request = HTTP::Request->new(PUT => $url);
    $request->header( 'x-api-key' => $self->{_apiKey} );
    $request->content_type('application/json');
    $request->content($jsonMessage);
    my $webRequest = $ua->request($request);


    if ($webRequest->{'_rc'} == 200) {
    	return 1; # success.
    }
    else {
        print "url called is '$url'\n";
        warn $webRequest->decoded_content;  # or whatever
        warn $webRequest->status_line;
    	return 0;
    }

}




=head2 getAlbumId

Get the album id based on requested album name.


    my $albumId = $immich->getAlbumId($albumName);

=cut


sub getAlbumId
{
    my ($self, $wantedName) = @_;

    my $webHtml;
    my $urlPort = ($self->{_port} eq '') ? '' : ":$self->{_port}";
    my $url  = "$self->{_server}$urlPort";
       $url .= '/api/albums';

    my $jsonMessage  = qq({);
       $jsonMessage .= qq(});

    my $ua = LWP::UserAgent->new();
    $ua->agent( '$self->{_userAgent}' );
    my $request = HTTP::Request->new(GET => $url);
    $request->header( 'x-api-key' => $self->{_apiKey} );
    $request->content_type('application/json');
    $request->content($jsonMessage);
    my $webRequest = $ua->request($request);

    if ($webRequest->{'_rc'} == 200) {
        $webHtml =  $webRequest->decoded_content;  # or whatever
    }
    else {
        warn $webRequest->decoded_content;  # or whatever
        warn $webRequest->status_line;
    }
        
    my $json = JSON->new->allow_nonref;
    my $jsonText = $json->decode($webHtml);
    
    #print "jsonText follows:\n";
    #print Dumper($jsonText);
    
    foreach my $item (@$jsonText) {
        next unless ($item->{'albumName'} eq $wantedName);
        return $item->{'id'};

    }

}


=head2 deleteAlbum

Delete an album based on requested album id.


    my $rc = $immich->deleteAlbum($albumId);

=cut


sub deleteAlbum
{
    my ($self, $id) = @_;

    my $webHtml;
    my $urlPort = ($self->{_port} eq '') ? '' : ":$self->{_port}";
    my $url  = "$self->{_server}$urlPort";
       $url .= '/api/albums/';
       $url .= "$id";

    my $jsonMessage  = qq({);
       $jsonMessage .= qq(});

    my $ua = LWP::UserAgent->new();
    $ua->agent( '$self->{_userAgent}' );
    my $request = HTTP::Request->new(DELETE => $url);
    $request->header( 'x-api-key' => $self->{_apiKey} );
    my $webRequest = $ua->request($request);

    if ($webRequest->{'_rc'} == 200) {
        $webHtml =  $webRequest->decoded_content;  # or whatever
        return 1;
    }
    else {
        print "\n\n -=-=-> you may need to delete the album via the UI before running this script.\n\n";
        warn $webRequest->decoded_content;  # or whatever
        warn $webRequest->status_line;
        return 0;
    }
        

}


=head2 createAlbum

Create a new album based on requested album name and description

    $jsonMessage  = qq({);
    $jsonMessage .= <<"EOFj";
  "albumName": "$albumName",
  "description": "$albumDesc"

EOFj
       $jsonMessage .= qq(});

    my $rc = $immich->createAlbum($albumName);

=cut


sub createAlbum
{
    my ($self, $requestIn) = @_;

    my $webHtml;
    my $urlPort = ($self->{_port} eq '') ? '' : ":$self->{_port}";
    my $url  = "$self->{_server}$urlPort";
       $url .= '/api/albums/';

    my $ua = LWP::UserAgent->new();
    $ua->agent( '$self->{_userAgent}' );
    my $request = HTTP::Request->new(POST => $url);
    $request->header( 'x-api-key' => $self->{_apiKey} );
    $request->content_type('application/json');
    $request->content($requestIn);

    my $webRequest = $ua->request($request);

    if ($webRequest->{'_rc'} == 201) {
        $webHtml =  $webRequest->decoded_content;  # or whatever
        return 1;
    }
    else {
        warn $webRequest->decoded_content;  # or whatever
        warn $webRequest->status_line;
        return 0;
    }
        

}



=head2 addAssetToAlbum

Create a new album based on requested album name and description

    $jsonMessage  = qq({);
    $jsonMessage .= <<"EOFj";
  "albumName": "$albumName",
  "description": "$albumDesc"

EOFj
       $jsonMessage .= qq(});

    my $rc = $immich->addAssetToAlbum($albumName);

=cut


sub addAssetToAlbum
{
    my ($self, $requestIn, $album) = @_;

    my $webHtml;
    my $urlPort = ($self->{_port} eq '') ? '' : ":$self->{_port}";
    my $url  = "$self->{_server}$urlPort";
       $url .= '/api/albums';
       $url .= "/$album/assets";

    my $ua = LWP::UserAgent->new();
    $ua->agent( '$self->{_userAgent}' );
    my $request = HTTP::Request->new(PUT => $url);
    $request->header( 'x-api-key' => $self->{_apiKey} );
    $request->content_type('application/json');
    $request->content($requestIn);

    my $webRequest = $ua->request($request);

    if ($webRequest->{'_rc'} == 200) {
        $webHtml =  $webRequest->decoded_content;  # or whatever
    }
    else {
        warn $webRequest->decoded_content;  # or whatever
        warn $webRequest->status_line;
        print "tried to add asset ($album)\n\t$requestIn\n\n";
    }
        
    
    my $json = JSON->new->allow_nonref;
    my $jsonText = $json->decode($webHtml);
    
    #print "jsonText follows:\n";
    #print Dumper($jsonText);
    
    foreach my $item (@$jsonText) {
        #print Dumper($item);
        #print "-=-=-> $item->{'error'}\n";
        return $item->{'error'};
    }


}



=head2 getLibraryId

Create a new album based on requested album name and description

    $jsonMessage  = qq({);
    $jsonMessage .= <<"EOFj";
  "albumName": "$albumName",
  "description": "$albumDesc"

EOFj
       $jsonMessage .= qq(});

    my $rc = $immich->getLibraryId($albumName);

=cut


sub getLibraryId
{
    my ($self, $wantedName) = @_;

    my $webHtml;
    my $urlPort = ($self->{_port} eq '') ? '' : ":$self->{_port}";
    my $url  = "$self->{_server}$urlPort";
       $url .= '/api/libraries';
       #$url .= "/$album/assets";

    my $jsonMessage  = qq({);
       $jsonMessage .= qq(});
       
    my $ua = LWP::UserAgent->new();
    $ua->agent( '$self->{_userAgent}' );
    my $request = HTTP::Request->new(GET => $url);
    $request->header( 'x-api-key' => $self->{_apiKey} );
    $request->content_type('application/json');
    $request->content($jsonMessage);

    my $webRequest = $ua->request($request);

    if ($webRequest->{'_rc'} == 200) {
        $webHtml =  $webRequest->decoded_content;  # or whatever
    }
    else {
        warn $webRequest->decoded_content;  # or whatever
        warn $webRequest->status_line;
    }
        
    
    my $json = JSON->new->allow_nonref;
    my $jsonText = $json->decode($webHtml);

    #print "jsonText follows:\n";
    #print Dumper($jsonText);
    
    foreach my $item (@$jsonText) {
        #print Dumper($item);
        #print "\n-=-=-> $item->{'name'},  $item->{'id'}\n";
        next unless ($item->{'name'} eq $wantedName);

        #print "\n-=-=-> $item->{'name'},  $item->{'id'}\n";
        return $item->{'id'};

    }

}



=head2 scanLibrary

Create a new album based on requested album name and description

    $jsonMessage  = qq({);
    $jsonMessage .= <<"EOFj";
  "albumName": "$albumName",
  "description": "$albumDesc"

EOFj
       $jsonMessage .= qq(});

    my $rc = $immich->scanLibrary($albumName);

=cut


sub scanLibrary
{
    my ($self, $id) = @_;

    my $webHtml;
    my $urlPort = ($self->{_port} eq '') ? '' : ":$self->{_port}";
    my $url  = "$self->{_server}$urlPort";
       $url .= '/api/libraries';
       $url .= "/$id/scan";

    my $jsonMessage  = qq({);
       #$jsonMessage .= qq( "refreshModifiedFiles": true );
       $jsonMessage .= qq(});
       
    my $ua = LWP::UserAgent->new();
    $ua->agent( '$self->{_userAgent}' );
    my $request = HTTP::Request->new(POST => $url);
    $request->header( 'x-api-key' => $self->{_apiKey} );
    $request->content_type('application/json');
    $request->content($jsonMessage);

    my $webRequest = $ua->request($request);

    if ($webRequest->{'_rc'} == 204) {
        $webHtml =  $webRequest->decoded_content;  # or whatever
    }
    else {
        warn $webRequest->decoded_content;  # or whatever
        warn $webRequest->status_line;
    }
           
    print "..... done.\n"; 
    return $webHtml;

}



=head2 getJobs

Create a new album based on requested album name and description

    $jsonMessage  = qq({);
    $jsonMessage .= <<"EOFj";
  "albumName": "$albumName",
  "description": "$albumDesc"

EOFj
       $jsonMessage .= qq(});

    my $rc = $immich->getJobs($albumName);

=cut


sub getJobs
{
    my ($self, $asset_ref) = @_;

    my $webHtml;
    my $urlPort = ($self->{_port} eq '') ? '' : ":$self->{_port}";
    my $url  = "$self->{_server}$urlPort";
       $url .= '/api/jobs';

       
    my $ua = LWP::UserAgent->new();
    $ua->agent( '$self->{_userAgent}' );
    my $request = HTTP::Request->new(GET => $url);
    $request->header( 'x-api-key' => $self->{_apiKey} );
    $request->header( 'Accept' => 'application/json' );
    $request->content_type('application/json');

    my $webRequest = $ua->request($request);

    if ($webRequest->{'_rc'} == 200) {
        $webHtml =  $webRequest->decoded_content;  # or whatever
    }
    else {
        warn $webRequest->decoded_content;  # or whatever
        warn $webRequest->status_line;
    }
           
    my $json = JSON->new->allow_nonref;
    my $jsonText = $json->decode($webHtml);
    
    #print "jsonText follows:\n";
    #print Dumper($jsonText);

    %{$asset_ref} = %{$jsonText};
    print "..... done.\n"; 

}




=head2 getDuplicateAssets

Create a new album based on requested album name and description

    $jsonMessage  = qq({);
    $jsonMessage .= <<"EOFj";
  "albumName": "$albumName",
  "description": "$albumDesc"

EOFj
       $jsonMessage .= qq(});

    my $rc = $immich->getDuplicateAssets($albumName);

=cut


sub getDuplicateAssets
{
    my ($self, $asset_ref) = @_;

    my $webHtml;
    my $urlPort = ($self->{_port} eq '') ? '' : ":$self->{_port}";
    my $url  = "$self->{_server}$urlPort";
       $url .= '/api/duplicates';

       
    my $ua = LWP::UserAgent->new();
    $ua->agent( '$self->{_userAgent}' );
    my $request = HTTP::Request->new(GET => $url);
    $request->header( 'x-api-key' => $self->{_apiKey} );
    $request->header( 'Accept' => 'application/json' );
    $request->content_type('application/json');

    my $webRequest = $ua->request($request);

    if ($webRequest->{'_rc'} == 200) {
        $webHtml =  $webRequest->decoded_content;  # or whatever
    }
    else {
        warn $webRequest->decoded_content;  # or whatever
        warn $webRequest->status_line;
    }
           
    my $json = JSON->new->allow_nonref;
    my $jsonText = $json->decode($webHtml);
    
    #print "jsonText follows:\n";
    #print Dumper($jsonText);

    foreach my $duplicate (@{ $jsonText } ) {
        #print "duplicate follows:\n";
        #print Dumper($duplicate);
        foreach my $asset (@{ $duplicate->{'assets'} } ) {
            #print "asset follows:\n";
            #print ">$asset<\n";
            #print Dumper($asset);
            #print "---> $asset->{'id'}\n";
            push @$asset_ref, $asset->{'id'};
        }
    }

}




=head2 getAlbumInfo

Get the album id based on requested album name.


    my $albumId = $immich->getAlbumInfo($albumName);

=cut


sub getAlbumInfo
{
    my ($self, $id, $asset_ref) = @_;

    my $webHtml;
    my $urlPort = ($self->{_port} eq '') ? '' : ":$self->{_port}";
    my $url  = "$self->{_server}$urlPort";
       $url .= '/api/albums';
       $url .= "/$id" unless ($id =~ m/^\?/);
       $url .= "$id" if ($id =~ m/^\?/);

    my $ua = LWP::UserAgent->new();
    $ua->agent( '$self->{_userAgent}' );
    my $request = HTTP::Request->new(GET => $url);
    $request->header( 'x-api-key' => $self->{_apiKey} );
    $request->content_type('application/json');

    my $webRequest = $ua->request($request);

    if ($webRequest->{'_rc'} == 200) {
        $webHtml =  $webRequest->decoded_content;  # or whatever
    }
    else {
        warn $webRequest->decoded_content;  # or whatever
        warn $webRequest->status_line;
    }
        
    my $json = JSON->new->allow_nonref;
    my $jsonText = $json->decode($webHtml);
    
    #print "jsonText follows:\n";
    #print Dumper($jsonText);

    if (ref($jsonText) eq 'ARRAY') {
	    @{$asset_ref} = @{$jsonText};
    } elsif (ref($jsonText) eq 'HASH') {
	    %{$asset_ref} = %{$jsonText};
    }

    #push @{$asset_ref}, @{$jsonText->{'assets'}->{'items'}};
    
    #foreach my $item (@{$jsonText[0]->{'assets'}}) {
    #    my $fileName = $item->{'originalPath'};
    #    $assets_ref->{$fileName} = 1;
    #
    #}

}


=head2 deleteAssetFromAlbum

Get the album id based on requested album name.


    my $albumId = $immich->deleteAssetFromAlbum($albumName);

=cut


sub deleteAssetFromAlbum
{
    my ($self, $asset, $album) = @_;

    my $webHtml;
    my $urlPort = ($self->{_port} eq '') ? '' : ":$self->{_port}";
    my $url  = "$self->{_server}$urlPort";
       $url .= '/api/albums';
       $url .= "/$album/assets";

    my $jsonMessage  = qq({);
       $jsonMessage .= qq( "ids" : [ );
       $jsonMessage .= qq($asset);
       $jsonMessage .= qq( ] );
       $jsonMessage .= qq(});
       
    my $ua = LWP::UserAgent->new();
    $ua->agent( '$self->{_userAgent}' );
    my $request = HTTP::Request->new(DELETE => $url);
    $request->header( 'Accept' => 'application/json' );
    $request->header( 'x-api-key' => $self->{_apiKey} );
    $request->content_type('application/json');
    $request->content($jsonMessage);


    my $webRequest = $ua->request($request);

    if ($webRequest->{'_rc'} == 200) {
        $webHtml =  $webRequest->decoded_content;  # or whatever
    }
    else {
        warn $webRequest->decoded_content;  # or whatever
        warn $webRequest->status_line;
    }
        
    my $json = JSON->new->allow_nonref;
    my $jsonText = $json->decode($webHtml);
    
    #print "jsonText follows:\n";
    #print Dumper($jsonText);
    
    foreach my $item (@$jsonText) {
        #print Dumper($item);
        #print "-=-=-> $item->{'error'}\n";
        return $item->{'error'};
    }

}



=head2 getAssetInfo

Get the album id based on requested album name.


    my $albumId = $immich->getAssetInfo($albumName);

=cut


sub getAssetInfo
{
    my ($self, $id, $asset_ref) = @_;

    my $webHtml;
    my $urlPort = ($self->{_port} eq '') ? '' : ":$self->{_port}";
    my $url  = "$self->{_server}$urlPort";
       $url .= '/api/assets';
       $url .= "/$id";

    if ($id eq '') {
	 print "id is blank. skipping call\n";
         return;
    }


    my $ua = LWP::UserAgent->new();
    $ua->agent( '$self->{_userAgent}' );
    my $request = HTTP::Request->new(GET => $url);
    $request->header( 'Accept' => 'application/json' );
    $request->header( 'x-api-key' => $self->{_apiKey} );
    $request->content_type('application/json');


    my $webRequest = $ua->request($request);

    if ($webRequest->{'_rc'} == 200) {
        $webHtml =  $webRequest->decoded_content;  # or whatever
    }
    else {
        print "\n";
        warn $url;
        warn $webRequest->decoded_content;  # or whatever
        warn $webRequest->status_line;
    }
        
    my $json = JSON->new->allow_nonref;
    my $jsonText = $json->decode($webHtml);
    
    #print "jsonText follows:\n";
    #print Dumper($jsonText);
    
    %{$asset_ref} = %{$jsonText};
    
}




=head2 getAllPeople

Returns all people to a array reference.

    my @people;
    $immich->searchAssets($jsonMessage, \@people);

=cut


sub getAllPeople
{
    my ($self, $requestIn, $asset_ref, $progress) = @_;

    my $webHtml;
    my $urlPort = ($self->{_port} eq '') ? '' : ":$self->{_port}";
    my $url  = "$self->{_server}$urlPort";
       $url .= '/api/people';
    my $nextPage = 1;
    my $hasNextPage = 1;
    #my $progress = 0;


    until ($hasNextPage eq undef) {
        my $queryString  = $requestIn;
        $queryString .= qq(&page=$nextPage);
        my $requestUrl = "$url?$queryString";
    
        print "query string = $queryString\n" if ($self->{_debug});

        my $ua = LWP::UserAgent->new();
    	$ua->agent( '$self->{_userAgent}' );
        my $request = HTTP::Request->new(GET => $requestUrl);
        $request->content_type('application/json');
        $request->header( 'x-api-key' => $self->{_apiKey} );
    	#$request->content($jsonMessage);
    	#print "url = $requestUrl\n" if ($self->{_debug});
    	#print "request = $jsonMessage\n" if ($self->{_debug});

        my $webRequest = $ua->request($request);
        #print "web request = $webRequest\n";
        #print Dumper($webRequest);

        if ($webRequest->is_success) {
            $webHtml =  $webRequest->decoded_content;  # or whatever
        }
        else {
            warn $requestUrl;
            warn $queryString;
            die $webRequest->status_line;
        }

        my $json = JSON->new->allow_nonref;
        my $jsonText = $json->decode($webHtml);

    	if ($self->{_debug}) {
           print "jsonText follows:\n";
           print Dumper($jsonText);
           #exit 1;
    	}

        my $peopleSize = @{$jsonText->{'people'}};
        if ($peopleSize > 0) {
            $hasNextPage = 1;
            $nextPage++;
            #print "\tnext page number $nextPage\n";
        } else {
            $hasNextPage = undef;
        }

        #push @{$asset_ref}, @{$jsonText->{'people'}};
        foreach my $key (@{$jsonText->{'people'}}) {
            #print Dumper($key);
            $asset_ref->{$key->{'id'}}->{'name'} = $key->{'name'};
            $asset_ref->{$key->{'id'}}->{'birthDate'} = $key->{'birthDate'};
            $progress++;
            if ($progress) {
                print "people retrieved $progress\r" if ($progress % 100 == 0);
            }            

        }

        #my $keyCount = %$asset_ref;
        #print "\t\t$keyCount\n";
        #print Dumper($asset_ref);
        #exit 9;


    }

}




=head2 updatePerson

Get the album id based on requested album name.


    my $albumId = $immich->updatePerson($jsonMessage, $personId);

=cut


sub updatePerson
{
    my ($self, $requestIn, $id) = @_;

    my $webHtml;
    my $urlPort = ($self->{_port} eq '') ? '' : ":$self->{_port}";
    my $url  = "$self->{_server}$urlPort";
       $url .= '/api/people';
       $url .= "/$id";

    if ($id eq '') {
        print "id is blank. skipping call\n";
        return;
    }

    my $jsonMessage  = $requestIn;

    my $ua = LWP::UserAgent->new();
    $ua->agent( '$self->{_userAgent}' );
    my $request = HTTP::Request->new(PUT => $url);
    $request->header( 'Accept' => 'application/json' );
    $request->header( 'x-api-key' => $self->{_apiKey} );
    $request->content_type('application/json');
   	$request->content($jsonMessage);

    my $webRequest = $ua->request($request);

    if ($webRequest->{'_rc'} == 200) {
        $webHtml =  $webRequest->decoded_content;  # or whatever
        #my $json = JSON->new->allow_nonref;
        #my $jsonText = $json->decode($webHtml);
        
        #print "jsonText follows:\n";
        #print Dumper($jsonText);
        return 1;
    }
    else {
        print "\n";
        warn $url;
        warn $webRequest->decoded_content;  # or whatever
        warn $webRequest->status_line;
        return 0;
    }
        

}



sub getAllTags
{
    my ($self, $id, $asset_ref) = @_;

    my $webHtml;
    my $urlPort = ($self->{_port} eq '') ? '' : ":$self->{_port}";
    my $url  = "$self->{_server}$urlPort";
       $url .= '/api/tags';


    my $ua = LWP::UserAgent->new();
    $ua->agent( '$self->{_userAgent}' );
    my $request = HTTP::Request->new(GET => $url);
    $request->header( 'Accept' => 'application/json' );
    $request->header( 'x-api-key' => $self->{_apiKey} );
    $request->content_type('application/json');


    my $webRequest = $ua->request($request);

    if ($webRequest->{'_rc'} == 200) {
        $webHtml =  $webRequest->decoded_content;  # or whatever
    }
    else {
        print "\n";
        warn $url;
        warn $webRequest->decoded_content;  # or whatever
        warn $webRequest->status_line;
    }
        
    my $json = JSON->new->allow_nonref;
    my $jsonText = $json->decode($webHtml);
    
    print "jsonText follows:\n";
    print Dumper($jsonText);
    
    %{$asset_ref} = %{$jsonText};
    
}




=head1 AUTHORS

Len Veatch

=head1 COPYRIGHT

All rights reserved.

=head1 BUGS

Probably many

=cut


1;


