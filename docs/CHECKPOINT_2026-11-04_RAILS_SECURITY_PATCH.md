# Urgent Rails security patch — November 04 2026

The official Rails project released **8.1.4.1** on November 4, 2026,
addressing 21 issues, including Critical/High Active Storage vulnerabilities:
https://rubyonrails.org/2026/11/4/Rails-8.0.5.2-and-8.1.4.1-have-been-released

CI `bundle-audit check --update` flagged Rails 8.1.4 during the
drag-drop and Redis browser acceptance run. Brakeman and JS audit passed,
but the Ruby security gate correctly failed.

Action: require Rails 8.1.4.1 and lock Rails-framework component gems
to the same patch version. Do not suppress advisories, disable the gate,
or claim vulnerability-free software.

Acceptance: clean bundle install, full Rails tests/Redis-Chrome acceptance,
new Brakeman and advisory checks, Docker build and blob persistence.
No staging or production deployment is authorized.
