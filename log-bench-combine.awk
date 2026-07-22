#!/usr/bin/awk -f

BEGIN {
    FS="[|][ ]*"
}

/^MODEL_FAMILY/ { gsub(/^[^ ]+[ ]+/,"") ; model_family   = $0 }
/^MODEL_NAME/   { gsub(/^[^ ]+[ ]+/,"") ; model_name     = $0 }
/^MODEL_SPEC/   { gsub(/^[^ ]+[ ]+/,"") ; model_spec     = $0 }

# Match lines that contain the benchmark results
# We look for lines containing "pp512" or "tg128" to identify data rows
/^[|] .*(pp512|pp2048|pp4096|tg128)/ && !/---|-------/ {

    # fixup bogus model name.
    gsub(/gemma4 [?]B Q4_0/,"gemma4 12B Q4_0")

    gsub(/ +$/,"", $2)
    gsub(/ +$/,"", $3)
    gsub(/ +$/,"", $4)
    gsub(/ +$/,"", $5)
    gsub(/ +$/,"", $6)
    gsub(/ +$/,"", $7)
    gsub(/ +$/,"", $8)
    
    model = $2
    size = $3
    params = $4
    test = $7
    ts = $8

    # Initialize data for this model if seen for the first time
    if (!(model in map_size)) {
        map_size[model] = size
        map_params[model] = params
        map_family[model] = model_family
        map_spec[model] = model_name model_spec

        # Initialize columns to "N/A"
        results[model, "pp512"] = "N/A"
        results[model, "pp2048"] = "N/A"
        results[model, "pp4096"] = "N/A"
        results[model, "tg128"] = "N/A"
    }

    # Assign the t/s value to the correct test column using a concatenated key
    results[model, test] = ts
    # print "RESULTS[" model, test "]=| " ts " |"
}

# This part prints the results once the entire file is processed
END {
    # Define the header for our output table
    print ""
    print "| Model  | Size  | Params    | pp512     | pp2048    | pp4096    | tg128 |"
    print "| ---    | ---   | ---       | ---       | ---       | ---       | ---   |"
    for (m in map_size) {
        printf "| %s | %s | %s | %s | %s | %s | %s |\n", 
            m, 
            map_size[m], 
            map_params[m], 
            results[m, "pp512"], 
            results[m, "pp2048"], 
            results[m, "pp4096"], 
            results[m, "tg128"] | "sort"
    } 
    close("sort")
    # Define the header for our output table
    print ""
    print "| params | size   | pp512     | pp2048    | pp4096    | tg128     | model | family   | spec  |"
    print "| ---    | ---    | ---       | ---       | ---       | ---       | ---   | ---      | ---   |"
    for (m in map_size) {
        printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", 
            map_params[m], 
            map_size[m], 
            results[m, "pp512"], 
            results[m, "pp2048"], 
            results[m, "pp4096"], 
            results[m, "tg128"],
            m, 
            map_family[m],
            map_spec[m] | "sort -k 2n"
    } 
}
