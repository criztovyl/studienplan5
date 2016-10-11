var gulp = require('gulp');
var wiredep = require('wiredep').stream;
var mainBowerFiles = require('main-bower-files');
var browserSync = require('browser-sync');
var reload = browserSync.reload;

var bc = "bower_components/"

var dest = "dest";
var files = ["*.html", "css/*.css", "js/*.js"].concat(mainBowerFiles());
var fonts = [ bc + "bootstrap/dist/fonts/*" ];

// bower task handles index.html
gulp.task('default', ['fonts'], function() {
    gulp.src(files, {base: '.'})
    .pipe(wiredep())
    .pipe(gulp.dest(dest));
});


gulp.task('fonts', function(){
    gulp.src(fonts, {base: '.'})
    .pipe(gulp.dest(dest));
})


gulp.task('clean', function() {
});

// watch files for changes and reload
gulp.task('serve', ["default"], function() {
  browserSync({
    server: {
      baseDir: dest
    }
  });

  gulp.watch([files], {cwd: "."}, ["reload"]);
});

gulp.task('reload', ["default"], function() {
    reload();
});
