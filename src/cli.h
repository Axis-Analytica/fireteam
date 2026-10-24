#pragma once

#include <QByteArray>
#include <QStringList>

// The fireteam command line: list, show, plan, deploy, order, hold, abort,
// extract, discard, wait, skill install. Each takes --json, exits 0 on
// success and 1 on failure, and writes errors to stderr.
namespace Cli {
bool isCommand(const QByteArray &command);
int run(const QStringList &arguments);
}
