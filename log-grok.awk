#!/usr/bin/env awk
BEGIN {
    have_download = 0
    have_benchmark = 0
}
/^==== / {
    if (have_download) {
        print "```"
        print ""
        print "| real | user | sys  | time |"
        print "| ---- | ---- | ---- | ---- |"
        print "| "time_real " | " time_user " | " time_sys " |"
        print ""
    }
    if (have_benchmark) {
        print ""
        print "| real | user | sys  | time |"
        print "| ---- | ---- | ---- | ---- |"
        print "| "time_real " | " time_user " | " time_sys " |"
        print ""
    }
    have_download = have_benchmark = 0
}
/^==== Download/ {
    have_download = 1
}
/^==== Benchmark/ {
    have_benchmark = 1
}
/^MODEL_FAMILY/ {
    model_family = $2
}
/^MODEL_NAME/ {
    model_name = $2
}
/^MODEL_SPEC/ {
    model_spec = $2
}
/^[+] llama-completion / {
    print "### Download - " model_family
    print "| Model Family | Model Name |"
    print "| ----         | ----       |"
    print "| " model_family " | " model_name model_spec " |"
    print ""
    print "```"
    print $0
    print ""
}
/^[+] llama-bench / {
    print "### Benchmark - " model_family
    print "| Model Family | Model Name |"
    print "| ----         | ----       |"
    print "| " model_family " | " model_name model_spec " |"
    print ""
    print "```"
    print $0
    print "```"
    print ""
}
/ common_perf_print: .* time = / {
    print
}
/^[|] / {
    print $0
}
/^real\t[0-9]m/ {
    time_real = $2
}
/^user\t[0-9]m/ {
    time_user = $2
}
/^sys\t[0-9]m/ {
    time_sys = $2
}
END {
}   
