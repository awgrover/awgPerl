pms := $(shell find . -name '*.pm')

.dumy : pod

pod : Website.pod.html

Website.pod : $(pms)
        # extract the pod, substitute for a couple of places
	awk '/^=/,/^=cut/ {print} /^=cut/ {print ""}' Website.pm \
        | perl -p -e 's/^=head1 OtherTestsGoesHere/insert()/e; sub insert {open my $$f, "<Website/Element.pm"; "=cut\n\n".join "",<$$f>}' \
        | perl -p -e 's/^=head. OtherRequestsGoesHere/insert()/e; sub insert {open my $$f, "<Website/Form.pm"; "=cut\n\n".join "",<$$f>}' \
	> $@

Website.pod.html : Website.pod
	pod2html --title Test::Website --outfile $@ --infile $<
	rm pod2htm?.tmp

continuouspod :
	find . -name '*.pm' \
	| react -args make -f Website/Makefile '&&' echo '**/*.*'

