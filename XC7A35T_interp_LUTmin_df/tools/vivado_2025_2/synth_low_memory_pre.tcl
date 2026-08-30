# Vivado 2025.2 synthesis pre-hook for the 16 GB development host.
#
# The GUI otherwise starts two synthesis worker processes.  When Windows
# commit headroom is small, technology mapping can then terminate with an
# unhelpful "out of memory allocating ... bytes" message even though RTL
# elaboration completed correctly.  Keep the inner synthesis flow to one
# worker; the run launcher is independently kept at one job.
set_param general.maxThreads 1
puts "NF_SYNTH_LOW_MEMORY_PRE: general.maxThreads=1"
