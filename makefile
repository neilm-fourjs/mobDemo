# Automatic Makefile made by make4js by N.J.M.
all: rebuild etc/mobdemo.sch

rebuild:
	rm etc/mobdemo.sch 

etc/mobdemo.sch:
	cd etc && fgldbsch -db mobdemo -dv dbmpgs

bin/mdMob.42r:
	gsmake -t mobDemo mobDemo.4pw

clean:
	find . -name \*.42? -delete
