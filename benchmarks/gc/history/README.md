# Historical collector comparison

These logs and reports record the A/B tests run before the queue became the
sole collector. The `legacy` images used repeated whole-heap marker scans;
the `queue` images used the mark queue. Both had the same execution-context
refactor, benchmark source, board profile, and heap size.

`compare_results.py` and `compare_varied.py` validate and compare the saved
logs here. They are retained to reproduce the reported figures. Current
runtime builds no longer contain the legacy marker or its build switch, so
these scripts are not part of the current benchmark workflow. See the parent
directory's README for current build and capture commands.
