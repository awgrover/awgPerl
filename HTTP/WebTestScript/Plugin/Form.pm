package HTTP::WebTestScript::Plugin::Form;
use base qw(Exporter);
@EXPORT = qw(
	input
	clickButton
	set
	unset
	choose
	hwselect
	upload
        hidden
        submit
        form
        extractFormInfo
	);

use HTML::TokeParser;
use Verbose; $kVerbose = 0;
use Data::Dumper;

use strict;
use warnings;
no warnings 'uninitialized';

use Carp;
use HTTP::WebTestScript::Log;

our (
	$gCache, # clear me upon GET
        $killme,
	);

=head1 set|unset "comment", 'checkOrRadioBoxName'

Use the tag's value to set the checkbox or radioBox. 

For radioButtons, will set the first one.

For unset, will omit the param on submit.

=head1 set/unset "comment", checkOrRadioBoxName=>"value"

Explicitly set the correct checkbox, or radio button. 

For unset, unset all radioBoxes, or only unset one checkbox.

=cut
	
sub set
	{
	my ($formField, $value, $traceInfo) = _set('set',@_);
	 
	my $firstTime = 1;
        # vverbose 0,"checkboxes for  => $value ".Dumper($formField); use Data::Dumper;
	foreach my $aField (@$formField)
		{
		if ((!defined($value) && $firstTime) || $aField->{'value'} eq $value )
			{
			vverbose 4,"Set\n";
			$aField->{'checked'} = 'checked';
			$firstTime = 0;
			last if $aField->{'qname'} =~ /^CHECKBOX_/; # yech. should set an array
			next;
			}
			
		vverbose 4,"Whack\n";
		delete $aField->{'checked'} if $aField->{'qname'} =~ /^RADIO_/; # Submit will assemble extant values	
		}
        # vverbose 0,"checkboxes after for  => $value ".Dumper($formField); use Data::Dumper;
	trace(1,set=>{%$traceInfo});
	}

sub _set
	{
	my ($command) = shift @_;
	my ($comment) = (scalar(@_)>2 && scalar(@_) %2) ? shift(@_) : undef;
	my ($name,$value) = @_;
	
	vverbose 4,"$command $name => $value\n";
	
	my $formField = findRadioCheck($HTTP::WebTestScript::gResponse,$name);

	if (!$formField)
		{
		trace(0,$command=>{name=>$name,defined($value) ? (value=>$value) : (),description=>$comment,failed=>"not found in a form"});	
		croak "No radio/checkbox field '$name' found (did you specify a name=>value and forget 'description'?";
		}
	vverbose 4,"\tfound box '$name' ".scalar(@$formField)."\n";
		
	return ($formField, $value, {description=>$comment, name=>$name});
	}
	
sub findRadioCheck
	{
	my ($response,$name) = @_;
		
	my $formField = 
		findFormField($HTTP::WebTestScript::gResponse,'',
			attributes=> {name=>"CHECKBOX_$name",type=>'checkbox'})
		|| findFormField($HTTP::WebTestScript::gResponse,''
			,attributes=>{name=>"RADIO_$name",type=>'radio'})
		;	
	return $formField;
	}
		
sub unset
	{
	my ($formField, $value, $traceInfo) = _set('unset',@_);
		die "not implemented" if defined $value;
	
	foreach my $aField (@$formField)
		{
		#vverbose 4,"Whack\n";
		delete $aField->{'checked'}; # Submit will assemble extant values	
		}
	trace(1,unset=>{%$traceInfo});
	}

sub clearCache {$gCache=undef};

=head1 choose "comment", selectName=>"value"

Set a dropdown (name='selectName') to the value (the value of the 'value' attribute, not the display string).

('select' is a perl reserved word).

=cut

sub choose {hwselect(@_)}
sub hwselect
	{
	my ($comment) = (scalar(@_) %2) ? shift(@_) : undef;
	my ($name,$value) = @_;

	my $formField = findSelect($HTTP::WebTestScript::gResponse,$name);
	if (!$formField)
		{
		trace(0,select=>{name=>$name, value=>$value, failed=>"no select tag by that name"});
		croak "no <select '$name'> found";
		}
		
	if (validSelectValue($formField,$value))
		{
		$formField->{'selected'} = $value;
		trace(1,select=>{name=>$name, value=>$value});
		}
	else
		{
		trace(0,select=>{name=>$name, value=>$value, failed=>"value is not a option"});
		#vverbose 0,Dumper($formField);
		croak "attempt to set bad value '$value' for <select name=>'$name'>, valid values are ",
			join(",",sort(keys %{$formField->{'value'} }));
		}
	}

sub validSelectValue
	{
	my ($formField,$value) = @_;
	#vverbose 0,Dumper($formField); die; use Data::Dumper;
	my $values = $formField->{'value'};
	return exists $values->{$value};
	}
	
sub findSelect
	{
	my ($response, $name) = @_;
	
	my ($form,$formField) = findFirstFormField($HTTP::WebTestScript::gResponse,'',attributes=>{name=>"SELECT_$name"});
	
	return $formField;
	}
		
=head1 input name=>'value' [, type => '*']

Sets the value for the text, textarea or password field.

Use "set" for checkboxes, radios, and selects, OR specify type=>'*' to
set any type.

You can't set a submit or hidden field. Use "hidden" instead of "input".

Dies if the field doesn't exist.

=cut
		
sub hidden
        {
	my ($comment) = (scalar(@_) % 2) ? shift(@_) : undef;
	my ($name,$value) = @_;
	
	vverbose 4,"Set hidden $name=>$value\n";
	
	my ($form,$formField) = findFirstFormField($HTTP::WebTestScript::gResponse,'',
		attributes=>{name => "HIDDEN_$name"});
	if (!$formField)
		{
		trace(0,hidden=>{name=>$name,value=>$value,description=>$comment,failed=>"not found in a form"});	
		croak "No hidden field '$name' found";
		}
	vverbose 4,"\tfound field '$name', as ",$formField->{'realName'},"\n";
		
	formSet($formField,$value); # check constraints
	
	trace(1,hidden=>{name=>$name,value=>$value,description=>$comment});		
	}

sub input
	{
	my ($comment) = (scalar(@_) % 2) ? shift(@_) : undef;
	my ($name,$value, %args) = @_;
        my $formName; $formName = $args{'formName'} if exists $args{'formName'};
        my %types = (exists $args{'type'} && $args{'type'} eq '*')
            ? (TEXT => 'formSet',
                CHECKBOX => 'set',
                RADIO  => 'set',
                SELECT => 'choose')
            : (TEXT => 'formSet')
            ;
	
	vverbose 4,"Set INPUT $name=>$value\n";
	
	my ($form,$formField);
        # foreach wanted type (default is TEXT only)
        my $type;
        foreach (keys %types) {
            $type = $_;
            ($form,$formField) = findFirstFormField($HTTP::WebTestScript::gResponse,$formName,
		attributes=>{name => "${type}_$name"});
            last if $formField;
            }

	if (!$formField)
		{
		trace(0,input=>{name=>$name,value=>$value,
                    (exists $args{'type'} ? (type => $args{'type'}) : ()), 
                    description=>$comment,failed=>"not found in a form"});	
                my ($maybe,$all) = listFormFields($name);
		croak "No text/password field '$name' found (was <input> missing the 'type', thus defaulting to 'INPUT'?), maybe (".join(",",@$maybe).") out of (".join(",",@$all).")";
		}
	vverbose 4,"\tfound field $type '$name', as ",$formField->{'realName'},"\n";
		
        if ($type ne 'TEXT') {
            my $fn = $types{$type};
            no strict 'refs';
            &$fn($name,$value);
            use strict 'refs';
            }
        else {
            formSet($formField,$value); # check constraints
            }
	
	trace(1,input=>{name=>$name,value=>$value,description=>$comment});		
	}

=head2 upload name-of-input-field=>$fileName

Causes multi-part/form upload.

Uses the mechanism in HTTP::Common::Request, so the "part" that is the file will get a Content-Type header from some mime-type lookup.

=cut

sub upload
	{
	my ($comment) = (scalar(@_) % 2) ? shift(@_) : undef;
	my ($name,$value) = @_;
	
	# FIXME: figure out how to do a file-handle or just string content
	vverbose 4,"Set INPUT $name=>$value\n";
	
	my ($form,$formField) = findFirstFormField($HTTP::WebTestScript::gResponse,'',
		attributes=>{name => "FILE_$name"});
	if (!$formField)
		{
		trace(0,input=>{name=>$name,value=>$value,description=>$comment,failed=>"not found in a form"});	
		croak "No file field '$name' found";
		}
	vverbose 4,"\tfound field '$name', as ",$formField->{'realName'},"\n";
	if (! -r $value)
		{
		trace(0,input=>{name=>$name,value=>$value,description=>$comment,failed=>"file not found"});	
		croak "No file '$value' found";
		}
	formSet($formField,$value); # check constraints
	
	trace(1,input=>{name=>$name,value=>$value,description=>$comment});		
	}

=head1 clickButton description name=>'button name'
=head1 clickButton description type=>'type attribute'

Finds the first button with the name (or name='', type='$type'), submits the form it belongs to. 
All of the values you've set, as well as this buttons "name=value" are sent as a POST.

See "get".

=cut

# ' stupid editor

=head1 submit description id=>$x, action=>$y, $name=>$z

Finds the first form (matching first of id,action,name in order) and submits it.

=cut

sub submit
        {
	# assembles extant values
	my ($comment) = (scalar(@_) % 2) ? shift(@_) : undef;
	my (%args) = @_;
	my ($debug) =delete @args{qw(debug)};
	my ($name, $id, $action) = @args{qw(name id action debug)};
	#croak "\nNo NAME or TYPE supplied" if (!defined($name) && !defined($type) && !defined($value)) 
	#	|| $name.$type.$value eq '';
	
	my $forms = parseForms($HTTP::WebTestScript::gResponse);
        my $form;
        while (my($fname,$info) = each %$forms) {
            use Data::Dumper;

            foreach (qw(id action name)) {
                if (defined($args{$_}) && $args{$_} eq $info->{$_}) {
                    $form = $info;
                    last;
                    }
                }
            }
        if (!$form) {
		trace(0,submit=>{%args,description=>$comment,failed=>"not found in a form"});	
                croak "No form $id, $name, $action found";
                }
        my $url = $form->{'action'};
        $url = $HTTP::WebTestScript::gResponse->request->uri->clone if ((!defined($url) || $url eq '') && $form->{'method'} =~ /^get$/i);

	my ($params,$hasFile) = getParams($form);
	
	vverbose 4,"Params ",Dumper($params);
	HTTP::WebTestScript::_get(command=>'clickButton',name=>$name,url=>$url,description=>$comment,
		method=>uc($form->{'method'} || 'POST'),params=>$params,
		fileUpload=>$hasFile,
		debug=>$debug);	
	}

sub clickButton
	{
	# assembles extant values
	my ($comment) = (scalar(@_) % 2) ? shift(@_) : undef;
	my (%args) = @_;
	my ($name, $debug, $formName) =delete @args{qw(name debug formName)};
	#croak "\nNo NAME or TYPE supplied" if (!defined($name) && !defined($type) && !defined($value)) 
	#	|| $name.$type.$value eq '';
	
        vverbose 4,"look for BUTTON_$name ",join(",",%args),"\n";
	my ($form,$formField) = findFirstFormField($HTTP::WebTestScript::gResponse,$formName,
		attributes=>{ 
                        name => ($name ? "BUTTON_$name" : qr/^BUTTON_/),
			%args});

	if (!$formField)
		{
		trace(0,clickButton=>{name=>$name, %args,description=>$comment,failed=>"not found in a form"});	
		croak "No button/submit '$name' found";
		}

        local $Data::Dumper::Maxdepth=1;
	# vverbose 0,"\tfound button '$name'",Dumper($formField),"\n";

	my ($params,$hasFile) = getParams($form);
        local $Data::Dumper::Maxdepth=3;
	# vverbose 0,"\tform params(A):'",Dumper(@$params[-2,-1]),"\n";
        if ($formField->{'value'} && $formField->{'name'}) {
            # my %params = @$params;
            # $params{$formField->{'name'}} = $formField->{'value'};
            # $params = [%params];
            push @$params,($formField->{'name'}, $formField->{'value'});
            }
	
	my $url = $form->{'action'};
	
	# vverbose 0,"Params ",Dumper($params);
	HTTP::WebTestScript::_get(command=>'clickButton',name=>$name,url=>$url,description=>$comment,
		method=>uc($form->{'method'} || 'POST'),params=>$params,
		fileUpload=>$hasFile,
		debug=>$debug);	
	}

sub getParams
	{
	my ($formInfo) = @_;
	
	#use Data::Dumper; vverbose 0,Dumper($formInfo);
	my $fieldList = $formInfo->{'fields'};
        # local $Data::Dumper::Maxdepth=3;
	# vverbose 0,"fieldlist ",Dumper($fieldList);
	die if !$fieldList;
	
	my @kv;
	my $hasFile; 

	my $forceBug = join(",",@$fieldList);
	# while (my ($qName,$aField) = each (%$fieldList))
        foreach my $aField (@$fieldList)
		{
		next if !defined($aField->{'name'});
                my $qName = $aField->{'qname'};

		# vverbose 0,"collect $qName\n";
			#vverbose 0,Dumper($aField);
		my $v = $aField->{'value'};

		next unless defined($v);
		
		if ($qName =~ /^FILE_/)
			{
			# signifies a file, if Content-Type=>'form-data'
			$v = [ $aField->{'value'} ];
			next unless $v;
			$hasFile=1;
			}

		if ($qName =~ /^CHECKBOX_/ || $qName =~ /^RADIO_/)
			{
			next unless exists $aField->{'checked'};
			}
		
		if ($qName =~ /^SELECT_/)
			{
			vverbose 5,$aField->{'name'},"=>",(
				exists($aField->{'selected'}) 
				?  (defined($aField->{'selected'}) 
					? $aField->{'selected'} 
					: 'undef')
				: 'undef'
				) . "\n";
			next unless exists $aField->{'selected'};
			next unless defined $aField->{'selected'};
			$v = $aField->{'selected'};
			}

                next if ($qName =~ /^BUTTON_/);
		
		# vverbose 0,"\tcollected $qName=>$v\n";
		
		push @kv,($aField->{'name'},$v);
		}
		
	return (\@kv,$hasFile);
	}

sub formSet
	{
	my ($formField,$value) = @_;
	
	# validate formField/value (width, radio, select)
	
	$formField->{'value'} = $value;
	}
	
sub findFirstFormField
	{
	# returns the ($form,$field)
	my ($response,$formName) = (shift @_, shift @_);

	my $fields = findFormField($response, $formName, @_);
	return undef if !$fields;
	
        # vverbose 0,"first field ",join(",",%{$fields->[0]}),"\n";
	return ($fields->[0]->{'form'},$fields->[0]);
	}
		
sub form {
    # return the form with the name/id
    # my ($theFormName, $formInfo) = i%{ form() }
    my ($formName) = @_;
    my $forms = parseForms($HTTP::WebTestScript::gResponse);
    return $forms->{$formName};
    }

sub extractFormInfo {
    # the attributes can have regex's
    # Remember, if you supply a "name", you need to supply a TYPE_ prefix (also with regex's)
    my %attributes = @_;
    my $formName = delete $attributes{'form'};
    $formName = '' if !defined $formName;
    return findFormField($HTTP::WebTestScript::gResponse, $formName, attributes => \%attributes);
    }

sub findFormField
	{
	# returns the ($name,$fieldsList)
	# for buttons, input, select, textarea
	# prefix the field you are looking for with the type, eg. INPUT_username
	
	my ($response,$formName, %args) = @_;
	my %attribs = %{ $args{'attributes'} || {} };
	
	vverbose 4,"args ".join(",",%args),", attribs:",join(",",%attribs)."\n";
	#vverbose 0,"Findformfield " .($formName || "") ."[".join(",",%attribs),"]\n";

	my $forms = parseForms($response);
	#vverbose 0,Dumper($forms),"\n";
	#vverbose 0,join(",",%$forms),"\n";
	#vverbose 0,"forms ",scalar(keys %$forms),"\n";
	if ($formName ne '')
		{
                # warn "useing formname '$formName'";
		# specific form
		$forms = $forms->{$formName};
		vverbose 4,"Specific form '$formName' ",($forms ? join(" ",keys %$forms) : "undef"),"\n";
		if (! $forms)
			{
			warn "No form by name '$formName', did you mean to specify a form-name?";
			eval {confess}; warn $@;
			$forms = {};
			}
                else {
                    $forms = {$formName => $forms};
                    }
		}
	#vverbose 0,"formname '$formName' => ",scalar(keys %$forms),"\n";

	my @foundFields;
	# vverbose 0,"Want ",join(",",%attribs),"\n";
	while (my ($theFormName, $formInfo) = each %$forms)
		{
		#vverbose 0, Dumper($formInfo); use Data::Dumper;
		my $fields = $formInfo->{'fields'};
		vverbose 4,"IN $theFormName $fields\n";
		my $forceBug = join(",",@$fields); # the "each" won't run without this (on the third try) (why?)

		# vverbose 0,"\t fields ",join(",",@$fields),"\n";

		FIELD:
		# while (my ($fieldName,$fieldInfo) = each (%$fields))
                foreach my $fieldInfo (@$fields)
			{
                        local $Data::Dumper::Maxdepth=1;
			if (defined($attribs{'name'})) {
                            $attribs{'qname'} = $attribs{'name'};
                            delete  $attribs{'name'};
                            }

                        # vverbose 0,"\ttest ".$fieldInfo->{'qname'}." vs ",join(",",%attribs),"\n";
                        keys %attribs; # reset iterator
			while (my ($attribName, $attribValue) = each (%attribs))
				{
				# vverbose 0,"\t'$attribName' => '$attribValue' vs '".$fieldInfo->{$attribName}."'?\n";
                                if (ref($attribValue) eq 'Regexp'
                                        ? $fieldInfo->{$attribName} !~ /$attribValue/
                                        : $fieldInfo->{$attribName} ne $attribValue) {
                                    next FIELD;
                                    }
                                # vverbose 0,"\t !! '$attribName' => '$attribValue'\n";
				}

			#vverbose 0,"HIT ",Dumper($fieldInfo);
			#vverbose 0,"HIT ",%$fieldInfo,"\n";
                        vverbose 4,"HIT\n";
			push @foundFields,$fieldInfo;
			}
		}
	keys %$forms; # reset iterator

	#die Dumper(\@foundFields) if ref $foundFields[0]->{'form'};
	return scalar(@foundFields)
		? \@foundFields
		: undef;
	}

sub parseForms
	{
	# find all the forms, accumulate them and the fields	
	# including buttons, input, select, textarea
	# prefixes the field names with the type: eg. TEXT_password
	# Returns { $formName=> { fields => $fields, action=>$action, name=>$name, method=>$method }
	# The fields look like:
	#	{$fieldName => [ {form=>$formInfo, name=>$name, realName=>$realName, info=>$fieldAttributes} ] }
	my ($response) = @_;
	
	#vverbose 0,"Old form ", ((ref $gCache->{'forms'} eq 'HASH') ? join(" ",keys %{$gCache->{'forms'}}) : "not form! ". ref ($gCache->{'forms'})) ,"\n" if $gCache && $gCache->{'forms'};
	return $gCache->{'forms'} if $gCache && $gCache->{'forms'};
	#vverbose 0,"New form parse\n";
	
	my $p = HTML::TokeParser->new($response->content_ref);
	
	my @forms;
	
	while (my $tag = $p->get_tag('form'))
		{
		push @forms , parseBodyOfForm($tag,$p);
		}

	#vverbose 0,"Found ",scalar(@forms)," forms\n";

	my %forms;
	my $ct=0;
	foreach my $aForm (@forms)
		{
		my $name = $aForm->{'name'};
		
		# If the same form-name is repeated, add a ct to end of name
		if (exists $forms{$name})
			{
			$name .= $ct;
			$ct++;
			}

		$forms{$name}  = $aForm;
		}
		
	#use Data::Dumper; vverbose 0, Dumper(\%forms),"\n";
	#vverbose 0,"Forms ",join(" ",keys(%forms)),"\n";
	$gCache->{'forms'} = \%forms;
	
	return \%forms;
	}

sub parseBodyOfForm
	{
	# return 
	# 	{name=>"formname",info=>{method=>"get|post",action="theurl",fields=$fieldInfo}
	#   [ {name=>"TYPE_fieldName",realName=>"fieldName", form=>$formINfo, info=>{maxWidth=>n, etc., checked ... value ...} } ]
	# NB: for SELECT, value=>{ "valueAttribute"=>"stripped content" ... } of the <value> tags
	#     (see collectValueAndOption() for details of data)
	#     and selected=>"valueAttributeThatIsSelected" (possibly undef)
        # NB: If an attribute has a "/" at the end, we duplicate it without one
	my ($formTag,$parser) = @_;
	
	my $formAttr = $formTag->[1];
	my %form = (
            id=>$formAttr->{'id'},
            name=>$formAttr->{'name'} || $formAttr->{'action'},
            method=>$formAttr->{'method'}||"GET",action=>$formAttr->{'action'}, 
            fields => []);
		vverbose 2,"Form ",$form{'name'},"\n";
	
	my $fields = $form{'fields'};
	while (my $tag = $parser->get_tag( qw(input button select /form textarea) ))
		{
		# use Data::Dumper;vverbose 0,"tag: ".Dumper($tag)." ";
		last if $tag->[0] eq '/form'; # ###'
		my $attr = $tag->[1];

                # fix xhtml empty tag greediness
                my $lastAttrib = $tag->[2][-1];
                if ($lastAttrib =~ m|/$|) {
                    $attr->{$`} = ($attr->{$lastAttrib} eq $lastAttrib) ? $` : $attr->{ $lastAttrib};
                    delete $attr->{ $lastAttrib };
                    $tag->[2][-1] = $`;
                    }

		my $prefix;
		if (exists $attr->{'type'})
			{
			$prefix = $attr->{'type'};
			}
		else
			{
			$prefix = $tag->[0];
			}
                warn "screwed up tag? no 'type': ".$tag->[3] if !$prefix && $tag->[0] =~ /^input$/i;
		$prefix = uc($prefix);
		$prefix = "TEXT" if $prefix eq 'PASSWORD'; # because TEXT == PASSWORD to the user
		$prefix = "BUTTON" if $prefix eq 'SUBMIT'; # because SUBMIT == BUTTON to the user
	
		my $name = $prefix."_".$attr->{'name'};

		if ($prefix eq 'SELECT')
			{
			my ($valOpt,$selected) = collectValueAndOption($parser);
			$attr->{'value'} = $valOpt;
			$attr->{'selected'} = $selected;
			}
		
		if ($prefix eq 'TEXTAREA')
			{
			$name = 'TEXT_'.$attr->{'name'};
			$attr->{'value'} = $parser->get_text();
			}
		
		
                $attr->{'qname'} = $name;
		$attr->{'form'} = \%form;
		push @$fields, $attr;

		#if ($prefix eq 'SELECT')
		#	{
		#	vverbose 4,"SELECT ",Dumper($fields[-1]); use Data::Dumper;
		#	die "## debug SELECT ";
		#	}
		
		}
	
	return \%form;
	}

sub collectValueAndOption
	{
	# returns { valueAttribute"=>"text" ... }, value-of-selected-option
	# where the text is stripped of tags, whitespace collapsed
	# skipping <option> if it has no 'value' attribute
	# and only returning the last of duplicate 'value' attributes
	# only permits one "selected"
	# if nothing is selected, selected=>undef, and implies first option?
	my ($parser) = @_;

	my %vo;
	my $selected;
	
	while (my $tag = $parser->get_tag( qw(option /select) ))
		{
		last if $tag->[0] eq '/select';
		#vverbose 0,"TAG ",Dumper($tag);
		
		my $attr = $tag->[1];
		
		my $v = exists($attr->{'value'}) ? $attr->{'value'} : undef;
		$selected = $v if exists $attr->{'selected'};
		
		next unless defined $v;
		
		my $option = $parser->get_trimmed_text(qw(/option option /select)); # tolerant
		$vo{$v} = $option;
		}
	return (\%vo, $selected);
	}

sub _verify_select
	{
	my ($name,$value) = @_;
		
	croak "expected a VALUE to go with SELECT" if !defined $value;
	vverbose 4,"Look for $name=$value\n";
	
	my ($form,$fieldInfo) = findFirstFormField
		($HTTP::WebTestScript::gResponse,'',attributes=>{name=>"SELECT_$name"});
	if (!$fieldInfo)
		{
		return (0,"select by that name not found in a form".($form ? " '$form'" : ""));
		}
	
	my $extant = exists($fieldInfo->{'selected'})
		? $fieldInfo->{'selected'}
		: "";
	vverbose 4,"select name=>$name select=>'$extant'\n";
		
	my $rez = 
		ref($value) eq 'Regexp'
		? $extant =~ /$value/
		: $extant eq $value
		;
	
	return ($rez, $rez ? "" : "not found, value was '$extant'");
	}
			
sub _verify_field
	{
	# a TEXT or HIDDEN
	my ($args) = @_;
	my ($field, $value, $field2) = delete @$args{qw(input value field)};
		$field=$field2 if !$field;
	
	croak "expected a VALUE to go with FIELD" if !defined $value;
	
	vverbose 4,"Look for $field=$value\n";
	
	my $rez;
	my %traceInfo = (input=>$field, value=>$value);

	my ($form,$fieldInfo) = 
		findFirstFormField(
			$HTTP::WebTestScript::gResponse,
			'',
			attributes=>{name=>"TEXT_$field"}
			);
	if (!$form)
		{
		($form,$fieldInfo) = findFirstFormField(
				$HTTP::WebTestScript::gResponse,
				'',
				attributes=>{name=>"HIDDEN_$field"}
			);
		}

	if (!$fieldInfo)
		{
		$traceInfo{'failed'} = "not found in a form".($form ? " '$form'" : "");
		$rez = 0;
		}
	
	else
		{
		#vverbose 0,"field ",Dumper($fieldInfo);
		$traceInfo{'form'}=$form->{'name'};

		#use Data::Dumper;	vverbose 4,Dumper($fieldInfo)
		vverbose 4,"\tfound field '$field'=>".$fieldInfo->{'value'}."\n";
		
		if (!ref $value)
			{
			$rez = $fieldInfo->{'value'} eq $value;
			}
		else
			{
			$rez = $fieldInfo->{'value'} =~ /$value/;
			}
			
		vverbose 4,($rez ? "found " : "not found ")  .(defined($form) ? ($form.".") : "")."$field=$value\n";
		$traceInfo{'failed'} = "not found ".(defined($form) ? ($form->{'name'}.".") : "")."$field=$value, field='".$fieldInfo->{'value'}."'"
			if !$rez;
		}
		
	
	return ($rez,\%traceInfo);
	}

sub _verify_toggle
	{
	# a checkbox or radio
	my ($command,$field, $args) = @_;
	# no other args
	
	my $form = undef; # add to args later
	
	croak "expected a field-name to go with '$command'" if !defined $field;
	
	vverbose 4,"Look for ".(defined($form)?$form:"").".$field=$command\n";
	
	my $rez;
	my %traceInfo = ($command=>$field);

	my $formField = findRadioCheck($HTTP::WebTestScript::gResponse,$field);
		
	if (!$formField)
		{
		$traceInfo{'failed'} = "not found in a form".($form ? " '$form'" : "");
		$rez = 0;
		}
	
	else
		{
		#use Data::Dumper;	vverbose 4,Dumper($fieldInfo)
		vverbose 4,"\tfound field '$field'\n";
		
		my @isSet = grep {exists $_->{'checked'}} @$formField;
		$rez = scalar @isSet;
		
		$rez = !$rez if ($command eq 'unset');
				
		vverbose 4,"$command? =", ($rez ? "$command " : "not $command ")  .(defined($form) ? ($form.".") : "")."\n";
		$traceInfo{'failed'} = "not $command ".(defined($form) ? ($form.".") : "").$field
			if !$rez;
		}
		
	
	return ($rez,\%traceInfo);
	}

sub extractFromForm
	{
	# "description", type =>'tagName', [all=>1,] text=>"some text", someAttribute=>'some value', [fromForm=>1]
	my ($comment) = scalar(@_) %2 ? shift(@_) : undef;
	my %args = @_;
	my ($type, $name, $element, $all, $text) = delete @args{qw(type name element all text)};
	confess "Need at least 'type' and 'name'" if !$type || !$name;
	confess "Don't use 'text', not implemented for 'fromForm'" if $text;
	confess "Don't use 'element', use 'type' 'fromForm'" if $element;

	if ($all)
		{
		return findFormField(
			$HTTP::WebTestScript::gResponse,'',
			attributes=>{name=>uc($type)."_$name"}, %args);
		}
	else
		{
		my ($form,$formField) = 
			findFirstFormField($HTTP::WebTestScript::gResponse,'',
				attributes=>{name=>uc($type)."_$name"}, %args);
		return $formField;
		}
	}

sub listFormFields {
    my ($search) = @_;
    my @fieldList;
    my $forms = parseForms($HTTP::WebTestScript::gResponse);
    while (my ($formName,$formInfo) = each %$forms) {
        my $fields = $formInfo->{'fields'};
        foreach my $fieldInfo (@$fields) {
            my $fieldName = $fieldInfo->{'qname'};
            my ($type,$name) = $fieldName =~ /^([A-Z]+)_(.+)/;
            push @fieldList, $formName."::".$name."($type)";
            }
        }
    my @maybe;
    if (defined $search) {
        @maybe = grep {/\Q$search\E/} @fieldList;
        }
    # warn "forms: ".Dumper($forms)." ";
    return (\@maybe,\@fieldList);
    }
    
1;
