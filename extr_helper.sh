#!/usr/bin/env bash

# Completition for Bash:
#
#    _UseExtrHelper ()
#    {
#        local cur;
#        COMPREPLY=();
#        cur=${COMP_WORDS[COMP_CWORD]};
#        case $COMP_CWORD in
#            "1")
#                COMPREPLY=($( compgen -W "moodle ausbplan" -- $cur ))
#            ;;
#            "2")
#                COMPREPLY=($( compgen -f -- $cur ))
#            ;;
#            "3")
#                COMPREPLY=($( compgen -W "force overwrite" -- $cur ))
#            ;;
#        esac;
#        return 0
#    }
#    complete -F _UseExtrHelper ./extr_helper.sh
#
# Install completition:
# $ head -23 extr_helper.sh | tail -n19 | sed 's/^#    //' >> ~/.bash_completition && . ~/.bash_completition


###
# 1 - Declarations
# 2 - Functions
# 3 - CLI

# 1 - Declarations

DATA_DIR="data"

SRC_DIR="$DATA_DIR/src"
CONV_DIR="$DATA_DIR/conv"

HTML_DIR="$CONV_DIR/html"
XLS_DIR="$SRC_DIR/xls"
PDF_DIR="$SRC_DIR/pdf"
JSON_DIR="$CONV_DIR/json"

EXIT_OK=0
EXIT_HELP=6
EXIT_NO_SUCH_FILE=1
EXIT_MOODLE_NON_XLS=2
EXIT_AUSBPLAN_NON_PDF=3
EXIT_MOODLE_ALREADY_THERE=4
EXIT_AUSBPLAN_ALREADY_THERE=5

# 2 - Functions

display_usage() { echo "Usage: $0 extractor file [force]"; exit $EXIT_HELP; }
already_there_msg()
{
    # Args: exit_code
    echo "Already there :)" >&2
    echo "Use \"overwrite\" as third argument to overwrite." >&2
    exit $exit
}

copy_src_file()
{
    # Args: src file must_exist callback force
    # force - non-empty -> true
    src=$1
    src_dir=`dirname "$src"`
    src_name=`basename "$src"`

    file=$2
    file_dir=`dirname "$file"`
    file_name=`basename "$file"`

    must_exist=$3
    callback=$4
    force=$5

    if [ ! -f "$file_dir/$src_name" ] || ! cmp "$src" "$file_dir/$src_name" || [ $force ]; then
        cp "$src" "$file"
        ( cd "$file_dir" && ln -fs "$file_name" "$src_name" )
        $callback "$src" "$file"
    elif [ ! -f "$must_exist" ]; then
        ( cd "$file_dir" && ln -s "$src_name" "$file_name" )
        $callback "$src" "$file"
        rm -f "$file"
    else
        return 1
    fi
}

replace_suffix()
{
    # Args: string suffix_replace
    echo ${1/%.${1##*.}/$2}
}

# 3 - CLI

Action=$1
Src=$2
Third=$3

[ "$Third" == "force" ] && Force=1 || Force=
[ "$Third" == "overwrite" ] && Overwrite=1 || Overwrite=

# Help
[[ "$0" =~ ^-{1,2}h(elp)?$ ]] || [ -z "$1" ] || [ -z "$2" ] && { display_usage; }

mkdir -p $DATA_DIR $HTML_DIR $XLS_DIR $PDF_DIR $JSON_DIR

[ ! -f "$2" ] && { echo "No such file \"$2\"!"; exit $EXIT_NO_SUCH_FILE; }

Src_Name=`basename "$Src"`
New_Src_Name=`date +%Y-%m-%d-%s`_$Src_Name
LO_Tmpdir=`mktemp -d /tmp/libreoffice-XXXXXXXXXXXX`

trap "rm -rf $LO_Tempdir" EXIT INT

case "$Action" in
    moodle)

        [[ "$Src" =~ ^.*\.xlsx?$ ]] || [ $Force ] || { echo -e "Moodle expects a .xls(x) file.\nPlease use \"force\" as third argument to force extraction." >&2; exit $EXIT_MOODLE_NON_XLS; }

        parse_moodle_xls()
        {
            src_name=`basename "$1"`
            xls_file=$2

            # https://ask.libreoffice.org/en/question/1686/how-to-not-connect-to-a-running-instance/
            loffice "-env:UserInstallation=file://$LO_Tmpdir" --convert-to html "$xls_file" --outdir "$HTML_DIR"

            ( cd "$HTML_DIR" && ln -fs "`basename "$(replace_suffix "$xls_file" .html)"`" "$(replace_suffix "$src_name" .html)"; )
        }

        copy_src_file "$Src" "$XLS_DIR/$New_Src_Name" "$HTML_DIR/$(replace_suffix "$Src_Name" .html)" parse_moodle_xls $Overwrite || echo `already_there_msg $EXIT_MOODLE_ALREADY_THERE`
        ;;
    ausbplan|ausb_plan|ausbildungsplan)

        [[ "$Src" =~ ^.*\.pdf$ ]] || [ $Force ] || { echo -e "ausb_plan expects a .pdf file.\nPlease use \"force\" as third argument to force extraction." >&2; exit $EXIT_AUSBPLAN_NON_PDF; }

        pdf_file=

        parse_ausbplan_pdf()
        {
            src_name=`basename "$1"`
            pdf_file=$2

            json_file=$JSON_DIR/$(replace_suffix "$New_Src_Name" .json)

            # https://github.com/tabulapdf/tabula-java (Pure Java) or https://github.com/tabulapdf/tabula-extractor (JRuby)
            # -rf is not --recursive --force, it's --spreadsheet --format ;)
            tabula -ruf JSON "$pdf_file" > "$json_file"

            # tabula seems to produce invalid JSON. Make it valid.
            sed 's/\]\]\[\[/\],\[/g' -i "$json_file"

            ( cd "$JSON_DIR" && ln -fs "`basename "$json_file"`" "$(replace_suffix "$src_name" .json)" )
        }

        copy_src_file "$Src" "$PDF_DIR/$New_Src_Name" "$JSON_DIR/$(replace_suffix "$Src_Name" .json)" parse_ausbplan_pdf $Overwrite || already_there_msg $EXIT_AUSBPLAN_ALREADY_THERE

        ;;
    *)
        display_usage
        ;;
esac
