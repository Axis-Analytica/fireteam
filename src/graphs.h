#pragma once

#include <QString>
#include <QStringList>
#include <QVariantMap>

// Knowledge graphs of projects, made by graphify (github.com/Graphify-Labs/graphify)
// from the code alone, offline, and kept in Fireteam's data directory rather
// than in the project. Fireteam reads graphify's symbol-level graph.json and
// folds it into a map of files: what each file holds, which files lean on
// which, and the communities they form.
namespace Graphs {
// graphify, if it's installed: FIRETEAM_GRAPHIFY, then PATH, then the copy
// Fireteam installs into its data directory. Empty when there's none.
QString executable(const QString &dataDirectory);
// Where Fireteam's own copy lives when it installs one.
QString installDirectory(const QString &dataDirectory);
// The folder graphify writes a project's graph into (--out); graph.json is
// under its graphify-out/.
QString outputDirectory(const QString &dataDirectory, const QString &project);
QString graphFile(const QString &dataDirectory, const QString &project);
// The arguments that build a project's graph.
QStringList buildArguments(const QString &dataDirectory, const QString &project);

// The file-level map of a graph.json, laid out:
// {files: [{path, symbols, community, x, y, degree, top: [labels]}],
//  links: [{a, b, weight}] (indexes into files), communities: [{id, label, size}],
//  hubs: [{label, path, degree}], stats: {files, symbols, links, communities},
//  commit, builtAt}. Positions are in 0..1, the same for the same graph.
// Empty when the file can't be read.
QVariantMap view(const QString &graphJson);
// The symbols in one file and the files it's linked to, from the same graph:
// {symbols: [{label, line, degree}], neighbours: [{path, weight}]}.
QVariantMap fileDetail(const QString &graphJson, const QString &path);
// What an agent gets: the project's shape in a few lines, and how to ask the
// graph more. Empty without a view.
QString brief(const QVariantMap &view, const QString &graphJson, const QString &executable);
// The read-only graphify commands an agent may run without asking.
QStringList allowedRules(const QString &executable);
}
