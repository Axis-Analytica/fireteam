#pragma once

#include <QString>
#include <QStringList>
#include <QVariantList>

// What an agent changed, read from git without touching the user's work.
// Snapshots are commits of the whole working tree (untracked files included,
// ignored files not) built in a throwaway index and kept under hidden refs, so
// the user's index, branches, and stash never see them.
namespace Intel {
bool isRepository(const QString &directory);
// Records the working tree under ref and returns the commit, or an empty
// string when the directory isn't in a repository or git fails.
QString snapshot(const QString &directory, const QString &ref, const QString &message);
// One map per changed file: path, added, removed, status (A, M, D).
QVariantList changes(const QString &directory, const QString &from, const QString &to);
QString diff(const QString &directory, const QString &from, const QString &to, const QString &path);
// Puts the working tree back to the snapshot target, given a snapshot of the
// tree as it is now: files are rewritten from target, and files that target
// didn't have are deleted.
bool restore(const QString &directory, const QString &target, const QString &current);
// Deletes every ref under prefix (refs/fireteam/<id>/), letting git collect
// the snapshots in its own time.
void forget(const QString &directory, const QString &prefix);
}
