#!/usr/bin/guile \
--debug -e main -s
!#
;(define-module (awg template-awg test))
(use-modules (ice-9 debug))

(use-modules 
    (oop goops)
    (awg debug)
    (awg list)
    (awg string)
    (ice-9 match)
    (awg template base)
    (awg template awg)
    (awg render)
    (awg datapool)
    )

(define-class <test-obj> ()
	(volatile #:init-value 1 #:accessor volatile)
        )

(define-method (volatize (o <test-obj>))
	(set! (volatile o) (+ 1 (volatile o)))
	"")
(define-method (method2 (o <test-obj>)) "meth2")
(define-method (madeIt (o <test-obj>)) "made it")
(define-method (method1 (o <test-obj>)) o)
(define-method (trueA (o <test-obj>)) 1)

(add-datapool-visible <test-obj>
        'method2 method2
        'madeIt madeIt
        'method1 method1
        'volatile volatile
        'volatize volatize
        'trueA trueA)

(define template-data 
	(let ((obj (make <test-obj>)))
		(list->alist (list 
			'simpleFn (lambda () "interpolated fn value")
			'dieFn (lambda () (error "an interpolated fn that calls die"))
			'scalar 1
			'scalar1 "a scalar value"
			'scalarInt 9
			'scalarFloat 1.3
			'htmlChars "\" quoted, & anded, <> compared \""
			'obj obj
			'hash (list->hash (list 'a 1 'key1 obj 'key2 "val2"))
			'array (list->array (list 1 obj "elem2" 3))
			'cleanArray (list->array (list 1 "elem2" 3))
			'countingFn 
				(let (
					(ct 0) 
					(value '(zero once more-than-once))
					)
					(lambda () (set! ct (+ 1 ct))
						(list-ref value ct)))
			'zero 0
			'empty ""
			'oneBlank " "
			'anUndef nil
			'secondUndef '()
			'qstringValue "blah<>&\"' =#@%+blah"
			'cwd (getcwd)
			))
	))

(define (read-before-expected)
	(join-reverse "" (primitive-read-before-expected 0 '())))

(define (primitive-read-before-expected len sofar)
	(let (
		(aLine (read-line (current-input-port) 'concat))
		)
		(if (eof-object? aLine)
			sofar
			(if (equal? aLine "__EXPECTED__\n")
				sofar
				(primitive-read-before-expected (+ len (string-length aLine)) (cons aLine sofar))))))

(define test-data-file-name "template_test.tmpl")

(define (getTestData)
	(with-input-from-file test-data-file-name
		(lambda ()
			(let (
				(template (read-before-expected))
				(expected (read-delimited ""))
				)
				(list template expected)))))

; port-filename port


; ###

(define (diff a b)
	(system (string-append "diff " a " " b)))

(define (main . args)
	(debug-set! width 132)
	(debug "Data ") (write template-data) (newline)
	(debug "ARGS " args)
	(and (> (length (car args)) 1) 
            (set! test-data-file-name (cadr (car args))))
	(debug "template " test-data-file-name)
	(match-let* (
		((template expected) (getTestData))
		(temp-tmpl-name "/tmp/template-tmp.scm.XXXXXX")
		(temp-res-name "/tmp/template-res.scm.XXXXXX")
		(temp-exp-name "/tmp/template-exp.scm.XXXXXX")
		(temp-tmpl (mkstemp! temp-tmpl-name))
		(temp-result (mkstemp! temp-res-name))
		(temp-expected (mkstemp! temp-exp-name))
		(includer (lambda (parent filename . options) ; FIXME: make this the default includer
			(debug "Including " filename " options " options)
			(force-output temp-result)
			(awg:render  (debug-I "included-template"
				(apply make <awg:template:awg>
					#:perl5lib ".."
					#:file-path filename
					#:compiled-dir "/tmp"
					#:datapool template-data
					#:slot-cache (template:slot-cache parent)
					options ))
				temp-result)))
		(processor (make <awg:template:awg> 
			#:perl5lib ".."
			#:file-path temp-tmpl-name
			#:compiled-dir "/tmp"
			#:datapool template-data
			#:includer includer
			#:no-cache #t))
		)
		(display template temp-tmpl) (close-port temp-tmpl)
		(display expected temp-expected) (close-port temp-expected)

                ; The template must have a ".tmpl", but mkstemp must end in XXXXX.
                ; So, rename the file
                (rename-file temp-tmpl-name 
                    (string-append 
                        temp-tmpl-name 
                        "." (template-extension processor)))

                ; Required: call template-loadable? to resolve file name correctly
                (debug "Loadable? " (template-loadable? processor))

		(let ((raw 
				(with-output-to-string 
					(lambda () (awg:render processor awg:medium:raw)))))
			(if (not (equal? raw template)) 
				(error "Raw wasn't equal to template")
				(begin (display "OK   Raw equals template") (newline))))
		(flush-all-ports)
		(debug "Output to " temp-res-name)
		(awg:render processor temp-result) (close-port temp-result)
		(debug "Diff " temp-exp-name " " temp-res-name)
		(diff temp-res-name temp-exp-name)))
		
; (write template-data)
