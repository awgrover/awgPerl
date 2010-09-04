package Test::Website::Form;
use base qw(Exporter);
@EXPORT    = qw(
    submit
    set
    unset
    dump_forms
    );

use import qw(
    &Test::Website::_get
    %Test::Website::PageCache 
    &Test::Website::Element::_element 
    );

use warnings; use strict; no warnings 'uninitialized';

use HTML::TreeBuilder::XPath;
use Test::Website::Log;
use Data::Dumper;
use Carp;
use Verbose; $kVerbose = $ENV{'VERBOSE'} || 0;

=head2 submit <element-predicate>

Submit the matched form (see L<element-predicate|/_elementpredicate____>, must match a form, or a button. If it matches a form, this will include the first button in the posted params.

if you omit "tag", assumes

    tag => input, type => submit
    or tag => button

=head3 Short-hand submit 

For: 

    "use first button or form"

=head3 Short-hand submit "buttonname" 

For: 

    "use button named/value... OR form id/action/name|n ..."

=head2 submit href => "...", fields => { k=>v,...}

Submits a synthesized POST.

=cut

sub submit {
    # submit
    # submit pred...
    # submit $buttonname
    # submit $buttonname, pred...
    # submit href => $url, fields => ... 
    my ($buttonName, %args);
    vverbose 1,"\@_ ",join(",", @_);
    if (@_ == 0) {
        tie %args, 'Test::Website::Element::PredicateList' => ( tag => 'input', type => 'submit');
        submit_form(\%args);
        }
    elsif ( (scalar(@_) % 2) == 0) {
        tie %args, 'Test::Website::Element::PredicateList' => @_;
        if (defined $args{'href'}) {
            submit_explicit($args{'href'}, $args{'fields'});
            }
        else {
            submit_form(\%args);
            }
        }
    else {
        $buttonName = shift @_;
        tie %args, 'Test::Website::Element::PredicateList' => @_;
        $args{qr/^(id|name|action|value)$/} = $buttonName;
        vverbose 0,"Form";
        submit_form(\%args);
        }
    }

sub submit_explicit {
    my ($href, $fields) = @_;
    
    return
        _get(command=>'submit',
            url=>$href,
            method=>'POST',
            params=> ref($fields) eq 'HASH' ? [%$fields] : $fields,
            # fileUpload=>$hasFile,
            # debug=>$debug
            );

    }

sub submit_form {
    my ($args) = @_;

    my $moreParams = delete($args->{'moreParams'});

    vverbose 1,"args ",join(",",%$args);
    # button (or form)
    my $button = _element(%$args);
    if (!$button) {
        trace(0, 'submit' => $args, because => "No submit-button found");
        }
   
    if (!(
            $button->tag =~ /^form|button$/ 
            || ($button->tag eq 'input' && $button->attr('type') eq 'submit'))) {
        trace(0, 'submit' => $args, because => "Not form/button nor submit (tag = ".$button->tag.", type = ".$button->attr('type').")");
        }
    verbose "Submit via ".$button->starttag;

    my $formInfo = formInfo($button);
    if (!$formInfo) {
        my $i=1;
        my $ancestry = join("\n", map {(" " x $i++).$_->starttag} $button->lineage);
        trace(0, 'submit' => {@_}, because => "The submit-button ".$button->starttag." was not in a form: \n".$ancestry);
        }

    my @params;
    my $hasFile;
    if (0) { # was ($explicitParams)
        vverbose 2,"Form params from explicit...";
        # @params = @$explicitParams;
        }
    else {
        vverbose 2,"form fields ",join(" ",map {$_->tag} @{$formInfo->attr('_fields')});
        foreach (@{ $formInfo->attr('_fields') }) { 
            next if $_->tag eq 'input' && $_->attr('type') eq 'button';
            next if $_->tag eq 'input' && $_->attr('type') eq 'submit';
            next if $_->tag eq 'button';
            next if $_->tag eq 'input' && $_->attr('name') eq '';

            my $fv = $_->form_field_value; 
            if (scalar(@$fv)) { 
                vverbose 2,"collect ",join(",",@$fv);
                push @params, @$fv;
                }
            $hasFile |= $_->tag eq 'input' && $_->attr('type') eq 'file';
            }
        # and, of course, our button
        if ($button->tag eq 'input' && $button->attr('type') eq 'submit' && defined $button->attr('value')) {
            push @params, ($button->attr('name'), $button->attr('value')) if $button->attr('name');
            }
        }
    if ($moreParams) {
        if (ref($moreParams) eq 'ARRAY') {
            push @params, @$moreParams
            }
        else {
            push @params, %$moreParams
            }
        }
        
    vverbose 1,"submit params ".join(", ",@params);
    croak "file upload not implemented for ".$formInfo->starttag if $hasFile;

    # FIXME: implement these?
    my $debug = undef;

    my $url = $formInfo->attr('action');
    $url = $Test::Website::Response->request->uri->clone if ((!defined($url) || $url eq '') && $formInfo->attr('method') =~ /^get|post$/i); 
    croak "Url for the submit was empty" if !$url;
    return
        _get(command=>'submit',
            url=>$url,
            method=>uc($formInfo->attr('method') || 'GET'), 
            params=> \@params,
            fileUpload=>$hasFile,
            debug=>$debug);
    }

=head2 set value => "somevalue", <element-predicates>

Will set a form-field's value. Will find the first field that matches (the 'value' is not a predicate), of course.
Use the "form" predicate if necessary to pick a form.

    Form-field  Behavior
    text        fills in the value
    password    fills in the value
    textarea    fills in the value
    file        fills in the value (the file-name to be uploaded)
    select      "selects" an option (see below).
    checkbox    "checks" that checkbox (see below).
    radio       "checks" only that radio (un-checks the other of the same name) (see below).
    hidden      causes a failure (see "force => {}").

For a "select" field, the value must match one of it's "options". You can
match the value attribute, or the option's text.

For a checkbox and radio, the value must match an value attribute.

To set multiple checkboxes, or multiple options, use a regex value.
    
    set name="somecheckbox", value => qr/^[23]$/;
    set name="someselect", value => qr/^MD|MI|LA$/;

Of course, this fails if the matched element is not a form-field.

NB: You must provide some predicate in additino to "value=>v".

=head3 Short-hand set somefieldname => 'some value',... 

For: 

    set name=>"somefieldname", value=>"somevalue", ...

This is the most convenient form. 

There is some ambiquity here versus just a list of k=>v predicates. So, we try to treat the first k=>v as the "name" attribute, and "value" attribute. If that fails, we try to treat them as attributeName=>attributeValue.

=head3 Idiom set 'checkOrRadioOrSelectName' 

For: 

    "set the first radio/option, or all checkbox"

Convenient when there is only one checkbox/radio for a name. Will set all the options for a "multiple" "select".

=head3 Idiom set somename => undef 

For: 

    "unset the field"

That field will be omitted from submitted params.

=head3 Short-hand set <element-predicate for checkbox/radio/select> 

For: 

    set value => qr/./, <predicates...>

Only for radio/check/select.

You may omit the "value" for checkbox/radio/select. 

For radios, the first matching radio will be set; for checkboxes, all the matching checkboxes will be set.

For "select", if it is a "multiple",
then all the options of that "select" will be "selected"; for a non-multiple "select",
only the first option of the matched "select".

    set name=>"somecheckbox"; # sets all the checkboxes w/that name
    set name=>"someradio"; # sets first radio of that name
    set name=>"someselect"; # first of its options "selected"
    set name=>"multiselect"; # all of its options "selected"

=head3 force=> "somevalue", pred-for-hidden

You can only set a hidden field by using "force" instead of value.

=head3 Short-hand unset 'field' 

For: 

    set name=>'field', value=>'undef'

Unset's the field

=head3 Submitting arbitrary query-params

If you want to "set" a radio/checkbox/select to a non-existent "value", or add non-existent fields,
you'll have to use: submit force=>[]. See Submit.

=cut

sub unset {
    unshift @_, 'name' if @_ %2;
    goto &set(@_, value => undef);
    }

sub set {
    # 'name'
    # 'name' => 'value' # ambigous with a single k=>v pred
    # k=>v, ... # preds, 
    # NB: value => 'x' is not a pred for text|file|textarea|password
    # NB: a value => undef, is not a pred, it means unset
    # xpath(), ...
    # force => [ preds ]

    my %args;

    my ($tryKVFallback, $force);

    # xpath & 'name' short-hands
    if (@_ == 1) {
        if (ref $_[0] eq 'XPATH') {
            %args = ( xpath => $_[0] );
            }
        else {
            %args = (name => shift, value => qr/./);
            }
        }
    
    # fixup 'force', then deal with n=>v idiom
    else {
        tie %args, 'Test::Website::Element::PredicateList' => @_;
        # force becomes value
        if (exists $args{'force'}) {
            $force = 1;
            $args{'value'} = delete $args{'force'};
            vverbose 4,"found force value ".$args{'value'};
            }
=off
        foreach my $i (0..($#_ / 2)) {
            if ($_[$i*2 - 1] eq 'force') { 
                $force = 1;
                my $value = $_[$i*2 ];
                splice(@_, $i*2 - 1,2);
                splice(@_, 1, 0, $value);
                last;
                }
            }
=cut
        
        my $explicitValue;
        if (exists $args{'value'}) {
            $explicitValue = 1;
            }

        # either 'name'=>'value',... or k=>v,... (if we had $force, we had explicit value)
        if (!$explicitValue) {
            $tryKVFallback = 1; # we might have guessed 'name'=>'value' wrong
            my ($n,$v) = (shift, shift);
            unshift @_, ( name => $n, value => $v );
            tie %args, 'Test::Website::Element::PredicateList' => @_;
            }
        }
        
    verbose 0,"set args: ".join(", ",%args);

    my @forms = _element(_tag => 'form');
    foreach (@forms) {
        formInfo($_); # add _fields, etc.
        }
    if (!@forms) {
        trace(0, set => {%args}, because => "no form found");
        }

    # remove the 'value' pred, it might mean "unset" or "here's the new value"
    my ($value, $hasValue);
    if (exists $args{'value'}) {
        $hasValue = 1;
        $value = delete $args{'value'};
        vverbose 8,"removed value $value ",join(", ",%args);
        }

    vverbose 1,"find field ".join(", ",%args);

    # because 'value' may be a predicate for check/radio/select
    # we need to get a long candidate list, then possibly filter
    my $field = _element(_formfieldtype => qr/^text|password|textarea|file|select|checkbox|radio|hidden$/, %args);
    if (!$field && $tryKVFallback) {
        # revert from name=>'n', value => 'a' to:
        # n=>a as if 'n' was an attribute name, and 'a' was it's value
        my $a = delete $args{'name'};
        my $v = delete $args{'value'};
        $args{$a} = $v;
        vverbose 0,"revert to $a => $v";

        $field = _element(_formfieldtype => qr/^text|password|textarea|file|select|checkbox|radio|hidden$/, @_);
        }

    if (! $field) {
        my $ancestry = " in:\n\t"
            . join("\n\t", map { 
                $_->starttag."\n\t\t" 
                . join("\n\t\t", map { $_->starttag } @{ $_->attr('_fields') }) 
                } @forms)
            ;
        trace(0, set => {%args, ($hasValue ? (value=>$value) : ())}, because => "Field not found".($hasValue ? " ('value' not used as predicate)" : "") . $ancestry);
        }

    if (ref($value) eq 'Regexp' 
            && !($field->tag eq 'select'
                || $field->tag eq 'input' && $field->attr('type') =~ /^checkbox|radio$/)) {
        trace(0, set => {%args}, because => "Can't set value to a regex ($value) for ".$field->starttag);
        }

    croak "Can't set ".$field->attr('type')." without 'force': set force=>[".join(", ",%args)."]"
        if $field->tag eq 'input' && $field->attr('type') eq 'hidden' && !$force;

    vverbose 2,"set ".$field->starttag," = $value";
    my $newValues = $field->form_field_value($value);

    my $because;
    my $ok =1;
    if (defined $value) {
        $ok = @$newValues ? 1 : 0;
        vverbose 2,"set for spec [".join(', ',%args)."], v='$value', new=",join(",",@$newValues);
        $because = "value not set";
        if ($field->attr('_formfieldtype') eq 'select') {
            $because .= ", no such option '$value' in: "
                .join(", ",map {$_->attr('value')."(".($_->content_list)[0].")"} @{$field->attr('_options') })
                ;
            }
        }
    trace($ok, set => {%args}, because => $because);

    return $field;
    }

=head1 Method HTML::Element->form_field_value

An extension to HTML::Element, gives the "value" of a formfield:

    my $e = element 'select', name => "state";
    my $itsvalue = $e->form_field_value;

Will set the fields "value" if $value is given.

    $e->form_field_value("MD");

Works roughly like so:

    text|hidden|password : ->attr('value')
    radio/checkbox : ->attr('checked') & (->attr('value') || 1)
    select : value|text|1 of each ->attr('_options') that is selected
    textarea : ->content_list()[0]
    file : ->attr('value')

=cut

sub HTML::Element::form_field_value {
    # @value for <input>, text() for <textarea>, checked for radio/check/select.
    # Assumes the HTML::Elements have been marked up by formInfo()
    # Only 'select' elements should return more than 1 value
    my ($field, $newValue) = @_;
    my $shouldSet = scalar(@_) >= 2;
    
    vverbose 4,"field ".$field->starttag.($shouldSet ? (defined($newValue) ? " '$newValue'" : ' undef'): '');
    return [] if !defined $field->attr('name');

    Test::Website::Form::formInfo($field);

    my @values;
    if ($field->tag eq 'input') {
        if ($field->attr('type') =~ /^text|file|hidden|password$/ || ! defined $field->attr('type')) {
            if ($shouldSet) {
                $field->attr('value', $newValue);
                vverbose 3,"Set ".(defined($newValue) ? "'$newValue'" : 'undef');
                }
            if (defined $field->attr('value')) {
                vverbose 4,"input/\@text ".$field->attr('value');
                push @values, ($field->attr('name') => $field->attr('value'));
                }
            }
        elsif ( $field->attr('type') =~ /^checkbox|radio$/) {
            # present and "" is html, present and "checked" is xhtml
            if ($shouldSet) {
                vverbose 2,"set radio/check ".$field->attr('name')." if $newValue";
                # only one radio
                if ($field->attr('type') eq 'radio') {
                    my $ct=0;
                    foreach (@{ $field->attr('_form')->attr('_fields') }) {
                        if ($_->tag eq 'input' 
                                && $_->attr('type') eq 'radio' 
                                && $_->attr('name') eq $field->attr('name')
                                ) {
                            $_->attr('checked',undef);
                            }
                        $ct++;
                        }
                    vverbose 4,"reset radio ".$field->attr('name').", ct=$ct";
                    }

                my @fields = $field;

                # possibly set all checkboxes on (for matched value)
                if ($field->attr('type') eq 'checkbox') {
                    @fields =  grep {
                        $_->tag eq 'input' 
                            && $_->attr('type') eq 'checkbox' 
                            && $_->attr('name') eq $field->attr('name')
                        } @{ $field->attr('_form')->attr('_fields') };
                    vverbose 4,"set checkbox ct ".@fields;
                    }

                # only checkboxes will have n>1
                foreach my $aField (@fields) {
                    my $v = ($aField->attr('name') => 
                        (defined($aField->attr('value')) 
                            ? $aField->attr('value') 
                            : 1));
                    if (ref($newValue) eq 'Regexp' ? $v =~ $newValue : $v eq $newValue) {
                        $aField->attr('checked', 'checked');
                        vverbose 4,"SET!";
                        }
                    }
                }
            if (defined($field->attr('checked'))
                    && $field->attr('checked') =~ /^$|^checked$/i) {
                # use value if there, else 1
                vverbose 2,"input/\@check|radio is set ".$field->starttag;
                push @values, ($field->attr('name') 
                    => (defined($field->attr('value')) ? $field->attr('value') : 1));
                }
            }
        }
    elsif ( $field->tag eq 'select' ) {
        vverbose 4,"Select ".$field->starttag;
        my $setCt = 0; # for "only first if not multi-select"
        foreach my $option (@{ $field->attr('_options') }) {
            # present and "" is html, present and "checked" is xhtml
            if ($shouldSet) {
                $option->attr('selected',undef);
                vverbose 4,"\treseted ".$option->starttag;
                my $v = defined($option->attr('value')) 
                        ? $option->attr('value') 
                        : 1;
                my $t = defined($option->content_list)
                    ? ($option->content_list)[0]
                    : undef;
                if (ref($newValue) eq 'Regexp' 
                        ? ($v =~ $newValue || $t =~ $newValue) 
                        : ($v eq $newValue || $t eq $newValue)) {
                    vverbose 4,"\tselected?, setct $setCt, multi ".$field->attr('multiple');
                    if ($setCt == 0 || $field->attr('multiple')) {
                        vverbose 4,"\tselected!";
                        $option->attr('selected', 'selected');
                        $setCt++;
                        }
                    }
                }
            vverbose 4,"collect settings...".$option->starttag;
            if (defined($option->attr('selected'))
                    && $option->attr('selected') =~ /^$|^selected$/i) {
                vverbose 4,"\tselected/option";
                # use value if there, else 1
                push @values, ($field->attr('name') 
                    => (defined($option->attr('value')) 
                        ? $option->attr('value') 
                        : (defined($option->content_list) 
                            ? ($option->content_list)[0]
                            : 1)));
                }
            }
        }
    elsif ( $field->tag eq 'textarea' ) {
        if ($shouldSet) {
            @{$field->content_array_ref} = defined $newValue ? $newValue : ();
            }
        if ($field->content_list) {
            vverbose 4,"textarea/text()";
            push @values, ($field->attr('name') => ($field->content_list)[0]);
            }
        }
    return \@values;
    }

sub formInfo {
    # Find the enclosing form, and return it 
    # with _fields = list of field HTML::Elements,
    # where a 'select' element has _options = list of option HTML::Elements
    my ($elementNode) = @_;

    my $form = $elementNode->attr('_form') || $elementNode->look_up(_tag => 'form');
    vverbose 0,"no form for ".$elementNode->starttag." whose parent is ".$elementNode->parent->starttag if !$form;
    return undef if !$form;
    vverbose 1,"found form ".$form->starttag;

    return $PageCache{'form'}->{"".$form} if exists($PageCache{'form'}->{"".$form});

    my @tagsOfInterest = qw(input|textarea|submit|button|select);
    my $tagsOfInterest = join "|", @tagsOfInterest;
    my @fields = $form->look_down( _tag =>  qr/^$tagsOfInterest$/);

    # some psuedo attributes
    foreach (@fields) {
        $_->attr('_form',$form); # back ref

        # _formFieldType
        if ($_->tag =~ /^textarea|submit|button|select$/) {
            $_->attr('_formfieldtype', $_->tag);
            }
        else {
            $_->attr('_formfieldtype', $_->attr('type') || 'text');
            }

        # selects get their options
        next unless $_->tag =~ /^select$/i;
        $_->attr('_options', [ $_->look_down(_tag => 'option') ]);
        }

    $form->attr('_fields', \@fields);

    $PageCache{'form'}->{"".$form} = $form;

    return $form;
    }

sub dump_forms {
    my @info;
    my @f = Test::Website::Element::element(maybe => { tag => 'form'});
    if (!@f) {
        print "no form"
        }
    else {
        foreach my $f (@f) {
            push @info, Test::Website::Form::formInfo($f, 'includehidden')
            }

        # vverbose 0,Dumper(@info);
        foreach my $f (@info) {
            print $f->starttag,"\n";
            foreach my $field (@{$f->attr('_fields')}) {
                print "\t",$field->starttag,"\n";
                }
            }
        # dump_forms
        }
    }
1;
