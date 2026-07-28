#!/usr/bin/env awk
BEGIN {
    have_smoke = 0
    have_benchmark = 0
    n_models = 0
    list_models[0] = ""
}
/^==== / {
    if (have_smoke) {
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
    have_smoke = have_benchmark = 0
}
/^==== Smoke/ {
    have_smoke = 1
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
    print "### Smoke - " model_family
    print "| Model Family | Model Name |"
    print "| ----         | ----       |"
    print "| " model_family " | " model_name model_spec " |"
    print ""
    print "```"
    print $0
    print ""
    n_models++
    list_models[n_models] = "| " model_family " | " model_name model_spec " |"
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
    print ""
    print "### Models "
    print "| Model Family | Model Name |"
    print "| ----         | ----       |"
    for (i=1; i<=n_models; ++i) {
        print list_models[i]
    }
}   
