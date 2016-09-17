# studienplan5.rb
A utility to convert HTMLed-XLS Studienpläne into iCals.

It's under heavy development, so please take a look at other [branches](https://github.com/criztovyl/studienplan5/branches).

## Requirements

 - Nokogiri
 - iCalendar

With [Bundler](https://bundler.io/):

    $ bundler install


## XLS -> HTML

Use LibreOffice. My version\* also exports comments.

    loffice --convert-to html XLS_file

or

    soffice --convert-to html XLS_file


\* LibreOffice 5.1.2.1.0 10m0(Build:1)

## Usage

    Usage: ./studienplan5.rb [options] [FILE]

    FILE is a HTMLed XLS Studienplan.
    FILE is optional to be able to do -w/--web without reparsing everything.

        -c, --calendar                   Generate iCalendar files to "ical" directory. (Change with --calendar-dir)
        -j, --json                       Generate JSON data file (data.json).
        -d, --classes                    Generate JSON classes structure (classes.json).
        -o, --output NAME                Specify output target, if ends with slash, will be output directory. If not, will be name of calendar dir and suffix for JSON files.
        -k, --disable-json-object-keys   Stringify hash keys.
        -p, --json-pretty                Write pretty JSON data.
        -w, --web                        Export simple web-page for browsing generated icals. Does nothing unless -o/--output is a directory.
        -n, --calendar-dir NAME          Name for the diretory containing the iCal files. Program exits status 5 if -o/--output is specified and not a directory.
        -u, --disable-unified            Do not create files that contain all parent events recursively.
        -a, --disable-apache-config      Do not export .htaccess and other Apache-specific customizations.
        -h, --help                       Print this help.

## JSON data file format

    {
        json_object_keys: Bool,
        json_data_version: "x.y",
        generated: "%Y-%m-%d %H:%M:%S %z",
        data:  ...
    }

`json_data_version` is 1.0

### When `json_object_keys` is true
...`data` is an nested Array. At index 0 are the real keys, at index 1 is the hash where the keys are the index of the real key.
This is for preserving the Hash key objects. (JSON does not allow objects as keys)


    [
        [
            class,
            class,
            ...
        ],
        {
            0: [
                element,
                element,
                ...
            ],
            1: [
                element,
                element,
                ...
            ],
            ...
        }
    ]

 - `element` is `{ "json_class": "PlanElement", "v": [ TITLE, CLASS, ROOM, TIME, DUR, LECT, NR, SPECIAL, MORE ] }`
  + `class`/`CLASS` is `{ "json_class": "Clazz", "v": [ NAME, COURSE, CERT, JAHRGANG, GROUP ]`

### When it's false
...`data` is a hash, the keys are stringified as described below and the values are list's of `element`s, as the values above.

    {
        class: [
            element,
            element,
            ...
        ],
        class: [
            element,
            element,
            ...
        ],
        ...
    }

`class` is `Jahrgang JAHRGANG, CLASS, Course COURSE, Cert. CERT` (CLASS, COURSE and CERT are optional and can be missing, including corresponding text and comma)

### Values

 - TITLE: String
 - CLASS: `class` or String
 - ROOM: String
 - TIME: %Y-%m-%d %H:%M:%S %z
 - DUR: String (Rationale, i.e "3/4")
 - LECT: String; Lecturer
 - NR: String; Event number (#1, #2, ...)
 - SPECIAL: String; Currently only "fullWeek" to indicate event from Mon-Fri.
 - MORE: String; Comment.

 - NAME: String; Class name
 - COURSE: String; "BSc" or "BA"
 - CERT: String; "Fachberater", i.e. "FST", "FIS"
 - JAHRGANG: String; Name of the group of classes entered the training/studies in the same year.
 - GROUP: String; Group ID withing Jahrgang (one char)

## Author

Christoph "criztovyl" Schulz

 - [GitHub](https://github.com/criztovyl)
 - [Blog](https://criztovyl.joinout.de)
 - [Twitter @criztovyl](https://twitter.com/criztovyl)

## License
GPLv3 and later.

## <3

    <3
