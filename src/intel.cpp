#include "intel.h"

#include <QDir>
#include <QFile>
#include <QProcess>
#include <QTemporaryDir>
#include <QVariantMap>

namespace {

struct Git {
    bool ok = false;
    QByteArray out;
};

Git git(const QString &directory, const QStringList &arguments, const QString &index = {}) {
    QProcess process;
    process.setWorkingDirectory(directory);
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    // Snapshots are Fireteam's commits, so they don't need (or borrow) the
    // user's git identity.
    environment.insert("GIT_AUTHOR_NAME", "Fireteam");
    environment.insert("GIT_AUTHOR_EMAIL", "fireteam@localhost");
    environment.insert("GIT_COMMITTER_NAME", "Fireteam");
    environment.insert("GIT_COMMITTER_EMAIL", "fireteam@localhost");
    environment.insert("GIT_TERMINAL_PROMPT", "0");
    if (!index.isEmpty())
        environment.insert("GIT_INDEX_FILE", index);
    process.setProcessEnvironment(environment);
    process.setStandardInputFile(QProcess::nullDevice());
    process.start("git", arguments);
    if (!process.waitForFinished(30000)) {
        process.kill();
        process.waitForFinished(1000);
        return {};
    }
    return {process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0, process.readAllStandardOutput()};
}

QString text(const Git &result) { return QString::fromUtf8(result.out).trimmed(); }

// A copy of the real index, so `git add` only rehashes what changed, without
// ever writing to the real one.
QString scratchIndex(const QString &directory, const QTemporaryDir &scratch) {
    const QString index = scratch.filePath("index");
    const QString real = text(git(directory, {"rev-parse", "--path-format=absolute", "--git-path", "index"}));
    if (!real.isEmpty() && QFile::exists(real))
        QFile::copy(real, index);
    return index;
}

}

namespace Intel {

bool isRepository(const QString &directory) {
    return text(git(directory, {"rev-parse", "--is-inside-work-tree"})) == "true";
}

QString snapshot(const QString &directory, const QString &ref, const QString &message) {
    if (!isRepository(directory))
        return {};
    QTemporaryDir scratch;
    if (!scratch.isValid())
        return {};
    const QString index = scratchIndex(directory, scratch);
    if (!git(directory, {"add", "-A", ":/"}, index).ok)
        return {};
    const QString tree = text(git(directory, {"write-tree"}, index));
    if (tree.isEmpty())
        return {};
    QStringList commit{"commit-tree", tree, "-m", message};
    const QString head = text(git(directory, {"rev-parse", "--verify", "-q", "HEAD"}));
    if (!head.isEmpty())
        commit << "-p" << head;
    const QString sha = text(git(directory, commit));
    if (sha.isEmpty() || !git(directory, {"update-ref", ref, sha}).ok)
        return {};
    return sha;
}

QVariantList changes(const QString &directory, const QString &from, const QString &to) {
    QVariantList list;
    if (from.isEmpty() || to.isEmpty())
        return list;
    QHash<QString, QString> status;
    for (const QString &line : text(git(directory, {"diff", "--name-status", "--no-renames", from, to})).split('\n',
                                                                                                              Qt::SkipEmptyParts))
        status.insert(line.section('\t', 1), line.section('\t', 0, 0));
    for (const QString &line : text(git(directory, {"diff", "--numstat", "--no-renames", from, to})).split('\n',
                                                                                                         Qt::SkipEmptyParts)) {
        const QStringList parts = line.split('\t');
        if (parts.size() < 3)
            continue;
        // Binary files report "-" for both counts.
        list.append(QVariantMap{{"path", parts.at(2)}, {"added", parts.at(0).toInt()},
                                {"removed", parts.at(1).toInt()}, {"binary", parts.at(0) == "-"},
                                {"status", status.value(parts.at(2), "M")}});
    }
    return list;
}

QString diff(const QString &directory, const QString &from, const QString &to, const QString &path) {
    if (from.isEmpty() || to.isEmpty())
        return {};
    return QString::fromUtf8(git(directory, {"diff", "--no-renames", "--no-color", from, to, "--", ":/" + path}).out);
}

bool restore(const QString &directory, const QString &target, const QString &current) {
    if (target.isEmpty() || current.isEmpty())
        return false;
    const QString top = text(git(directory, {"rev-parse", "--show-toplevel"}));
    QTemporaryDir scratch;
    if (top.isEmpty() || !scratch.isValid())
        return false;
    const QString index = scratch.filePath("index");
    if (!git(top, {"read-tree", target}, index).ok || !git(top, {"checkout-index", "-a", "-f"}, index).ok)
        return false;
    // Files added since the target are removed, which restoring alone can't do.
    const Git added = git(top, {"diff", "--name-only", "--no-renames", "--diff-filter=A", "-z", target, current});
    if (!added.ok)
        return false;
    for (const QByteArray &path : added.out.split('\0'))
        if (!path.isEmpty())
            QFile::remove(QDir(top).filePath(QString::fromUtf8(path)));
    return true;
}

void forget(const QString &directory, const QString &prefix) {
    if (!isRepository(directory))
        return;
    for (const QString &ref : text(git(directory, {"for-each-ref", "--format=%(refname)", prefix})).split('\n', Qt::SkipEmptyParts))
        git(directory, {"update-ref", "-d", ref});
}

}
