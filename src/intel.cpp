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
    QByteArray err;
};

Git git(const QString &directory, const QStringList &arguments, const QString &index = {}, bool asFireteam = true) {
    QProcess process;
    process.setWorkingDirectory(directory);
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    // Snapshots are Fireteam's commits, so they don't need (or borrow) the
    // user's git identity. Commits of the agent's work are the user's.
    if (asFireteam) {
        environment.insert("GIT_AUTHOR_NAME", "Fireteam");
        environment.insert("GIT_AUTHOR_EMAIL", "fireteam@localhost");
        environment.insert("GIT_COMMITTER_NAME", "Fireteam");
        environment.insert("GIT_COMMITTER_EMAIL", "fireteam@localhost");
    }
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
    return {process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0, process.readAllStandardOutput(),
            process.readAllStandardError()};
}

QString text(const Git &result) { return QString::fromUtf8(result.out).trimmed(); }
QString errorText(const Git &result) {
    const QString error = QString::fromUtf8(result.err).trimmed();
    return error.isEmpty() ? QString::fromUtf8(result.out).trimmed() : error;
}

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

QString diffAll(const QString &directory, const QString &from, const QString &to, int limit) {
    if (from.isEmpty() || to.isEmpty())
        return {};
    const QString stat = text(git(directory, {"diff", "--stat", "--no-color", from, to}));
    QString patch = QString::fromUtf8(git(directory, {"diff", "--no-color", "--no-renames", from, to}).out);
    if (patch.size() > limit)
        patch = patch.left(limit) + QString("\n… cut at %1 KB; read the files themselves for the rest.\n").arg(limit / 1000);
    return stat + "\n\n" + patch;
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

QVariantMap repository(const QString &directory) {
    if (!isRepository(directory))
        return {{"git", false}, {"commits", false}};
    return {{"git", true},
            {"commits", git(directory, {"rev-parse", "--verify", "-q", "HEAD"}).ok},
            {"branch", text(git(directory, {"symbolic-ref", "--short", "-q", "HEAD"}))},
            {"top", text(git(directory, {"rev-parse", "--show-toplevel"}))}};
}

QString addWorktree(const QString &directory, const QString &path, const QString &branch, QString *error) {
    const QString top = text(git(directory, {"rev-parse", "--show-toplevel"}));
    if (top.isEmpty()) {
        *error = QStringLiteral("not a git repository");
        return {};
    }
    // A shelved operation picks its branch back up; a new one starts it.
    const bool exists = git(top, {"rev-parse", "--verify", "-q", "refs/heads/" + branch}).ok;
    const Git added = git(top, exists ? QStringList{"worktree", "add", path, branch}
                                      : QStringList{"worktree", "add", "-b", branch, path, "HEAD"});
    if (!added.ok) {
        *error = errorText(added);
        return {};
    }
    // Claude Code's personal settings for the project aren't tracked, so the
    // worktree gets a copy to keep the user's approvals.
    const QString settings = top + "/.claude/settings.local.json";
    if (QFile::exists(settings) && !QFile::exists(path + "/.claude/settings.local.json")) {
        QDir().mkpath(path + "/.claude");
        QFile::copy(settings, path + "/.claude/settings.local.json");
    }
    // That copy is personal, so the worktree's commits must never pick it up:
    // it goes in the repository's local exclude list, which isn't shared.
    const QString common = text(git(top, {"rev-parse", "--path-format=absolute", "--git-common-dir"}));
    if (!common.isEmpty()) {
        QFile exclude(common + "/info/exclude");
        QDir().mkpath(common + "/info");
        const QByteArray line = "/.claude/settings.local.json";
        QByteArray existing;
        if (exclude.open(QIODevice::ReadOnly)) {
            existing = exclude.readAll();
            exclude.close();
        }
        if (!existing.split('\n').contains(line) && exclude.open(QIODevice::Append))
            exclude.write((existing.isEmpty() || existing.endsWith('\n') ? QByteArray() : QByteArray("\n")) + line + "\n");
    }
    const QString relative = QDir(top).relativeFilePath(directory);
    return relative == "." ? path : QDir(path).filePath(relative);
}

bool commitAll(const QString &directory, const QString &message, QString *error) {
    if (!git(directory, {"add", "-A", ":/"}, {}, false).ok) {
        *error = QStringLiteral("git add failed");
        return false;
    }
    if (git(directory, {"diff", "--cached", "--quiet"}, {}, false).ok)
        return true;
    QStringList arguments{"commit", "-q", "--no-verify", "-m", message};
    // Without a git identity, the commit is signed as Fireteam rather than failing.
    if (text(git(directory, {"config", "user.email"}, {}, false)).isEmpty())
        arguments = QStringList{"-c", "user.name=Fireteam", "-c", "user.email=fireteam@localhost"} + arguments;
    const Git committed = git(directory, arguments, {}, false);
    if (!committed.ok)
        *error = errorText(committed);
    return committed.ok;
}

QString merge(const QString &directory, const QString &branch, const QString &message, QStringList *conflicts) {
    const QString top = text(git(directory, {"rev-parse", "--show-toplevel"}));
    const Git merged = git(top, {"merge", "--no-ff", "--no-edit", "-m", message, branch}, {}, false);
    if (merged.ok)
        return {};
    const QString unmerged = text(git(top, {"diff", "--name-only", "--diff-filter=U"}, {}, false));
    if (!unmerged.isEmpty()) {
        *conflicts = unmerged.split('\n', Qt::SkipEmptyParts);
        // Nothing is forced: the merge is undone and the conflicts reported.
        git(top, {"merge", "--abort"}, {}, false);
        return QStringLiteral("conflicts");
    }
    return errorText(merged);
}

bool removeWorktree(const QString &directory, const QString &path, const QString &branch, bool deleteBranch) {
    const QString top = text(git(directory, {"rev-parse", "--show-toplevel"}));
    if (top.isEmpty())
        return false;
    bool ok = !QDir(path).exists() || git(top, {"worktree", "remove", "--force", path}).ok;
    git(top, {"worktree", "prune"});
    if (deleteBranch && !branch.isEmpty())
        ok = git(top, {"branch", "-D", branch}).ok && ok;
    return ok;
}

void forget(const QString &directory, const QString &prefix) {
    if (!isRepository(directory))
        return;
    for (const QString &ref : text(git(directory, {"for-each-ref", "--format=%(refname)", prefix})).split('\n', Qt::SkipEmptyParts))
        git(directory, {"update-ref", "-d", ref});
}

}
