ROOT = ../..
REBAR = $(ROOT)/bin/rebar

DIALYZER=dialyzer
DIALYZER_OPTS=-Wno_return -Wrace_conditions -Wunderspecs -Wbehaviours
PLT_FILE=.gen_leader_plt
APPS=kernel stdlib erts compiler crypto


all: compile

compile:
	$(REBAR) compile

doc:
	$(REBAR) doc

plt: compile
	$(DIALYZER) --build_plt --output_plt $(PLT_FILE) --apps $(APPS) ./ebin/

check_plt: compile
	$(DIALYZER) --check_plt --plt $(PLT_FILE) --apps $(APPS) ./ebin/

analyze: compile
	$(DIALYZER) --plt $(PLT_FILE) $(DIALYZER_OPTS) -r ebin/

tests:
	$(REBAR) eunit

clean:
	$(REBAR) clean
