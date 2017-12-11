#!/usr/bin/python

# author: Matthew Wyczalkowski m.wyczalkowski@wustl.edu

# Create configuration files for SomaticWrapper based on template
# Usage:
#   python make_config.py [options] 

import sys

# key/value pairs in template and data file are delimited by =
# lines beginning with # are ignored
def read_key_value(params, f):
    for line in f:
        if line.startswith('#'): continue
        if not line.strip(): continue  # ignore blank lines
        key, val = line.partition("=")[::2]
        params[key.strip()] = val.strip()

    return params 

def main():
    from optparse import OptionParser
    usage_text = """usage: %prog [options] 
        Create configuration files for SomaticWrapper based on template

        Read key/value pairs from stdin or a file
            key/value pairs in template and data file are delimited by =
            lines beginning with # are ignored
        key/value pairs replace any which may be found in template
        Write to stdout or to a given file
    """

    parser = OptionParser(usage_text, version="$Revision: 1.2 $")
    parser.add_option("-i", dest="infn", default="stdin", help="Input filename")
    parser.add_option("-o", dest="outfn", default="stdout", help="Output filename")
    parser.add_option("-t", dest="template", default=None, help="Template filename")

    (options, params) = parser.parse_args()

    params = {}  

    # Read template first
    if options.template:
        params = read_key_value(params, open(options.template))

    if options.infn == "stdin":
        f = sys.stdin
    else:
        f = open(options.infn, 'r')

    # Now read from input (either stdin or another file).  Parameters here will replace those in template
    params = read_key_value(params, f)

    if options.outfn == "stdout":
        o = sys.stdout
    else:
        o = open(options.outfn, "w")

    # Finally, write output config file 
    for k in params:
        o.write(k + ' = ' + params[k] + "\n")

    f.close()
    o.close()

if __name__ == '__main__':
    main()

