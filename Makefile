# Shortcuts.  `make demo` = invent data, load it, build the warehouse, run the checks.
DB := $(or $(PGDATABASE),rental_dwh)
export PGDATABASE := $(DB)

demo: synthetic refresh

synthetic:
	python scripts/gen_synthetic.py raw_private

refresh:
	createdb $(DB) 2>/dev/null || true
	SKIP_BACKUP=1 bash scripts/run_all.sh

dashboard:
	python scripts/build_dashboard.py docs_site/dashboard.html

docs:
	cd dbt && dbt docs generate --static && mkdir -p ../docs_site && cp target/static_index.html ../docs_site/index.html

clean:
	rm -rf raw_private logs reports docs_site dbt/target
