#include "cli.h"
#include "command.h"
#include "operations.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLockFile>
#include <QSaveFile>
#include <QStandardPaths>
#include <QThread>
#include <QUuid>
#include <cstdio>

namespace {

const char *Usage = R"(Usage: fireteam [command]

  open                      the board (the default)
  serve                     run operations with no window
  list [--json]             every operation
  show <op> [--json]        one operation in detail
  plan --dir D --objective O [--codename C] [--cycles N] [--model M]
       [--roe restricted|free] [--handoff N] [--in-place] [--standing S]
       [--overwatch off|review|fix] [--deploy] [--json]
  deploy <op>               send it in (needs Fireteam running)
  order <op> <text> [--deploy]
  hold <op> | abort <op> | extract <op> | discard <op>
  wait <op> [--timeout S] [--json]
  skill install             install the agent skill for Claude Code

<op> is a codename, an id, or the start of an id.
)";

struct Arguments {
    QStringList positional;
    QHash<QString, QString> options;
    bool has(const QString &name) const { return options.contains(name); }
    QString value(const QString &name, const QString &fallback = {}) const { return options.value(name, fallback); }
};

// Flags that take no value; every other --option takes the next argument.
const QStringList Switches{"--json", "--deploy", "--in-place", "--worktree"};

Arguments parse(const QStringList &raw) {
    Arguments arguments;
    for (int i = 0; i < raw.size(); ++i) {
        const QString &argument = raw.at(i);
        if (argument.startsWith("--")) {
            if (Switches.contains(argument) || i + 1 >= raw.size())
                arguments.options.insert(argument, "1");
            else
                arguments.options.insert(argument, raw.at(++i));
        } else {
            arguments.positional << argument;
        }
    }
    return arguments;
}

void out(const QByteArray &text) { std::fputs(text.constData(), stdout); }
int fail(const QString &message) {
    std::fprintf(stderr, "fireteam: %s\n", qPrintable(message));
    return 1;
}

QString dataDirectory() {
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/fireteam";
}

// Whether the board or `fireteam serve` holds the data.
bool appRunning() {
    QDir().mkpath(dataDirectory());
    QLockFile probe(Command::lockPath(dataDirectory()));
    probe.setStaleLockTime(0);
    if (probe.tryLock(0)) {
        probe.unlock();
        return false;
    }
    return true;
}

QJsonArray savedOperations() {
    QFile file(dataDirectory() + "/operations.json");
    return file.open(QIODevice::ReadOnly) ? QJsonDocument::fromJson(file.readAll()).array() : QJsonArray();
}

// Hands a request to the running app and waits for its answer.
QJsonObject ask(const QJsonObject &request) {
    const QString inbox = Command::inboxPath(dataDirectory());
    QDir().mkpath(inbox);
    const QString name = QUuid::createUuid().toString(QUuid::WithoutBraces);
    QSaveFile file(inbox + "/" + name + ".json");
    if (!file.open(QIODevice::WriteOnly))
        return {{"ok", false}, {"error", "Couldn't write to Fireteam's inbox."}};
    file.write(QJsonDocument(request).toJson(QJsonDocument::Compact));
    file.commit();
    QElapsedTimer clock;
    clock.start();
    const QString result = inbox + "/" + name + ".result.json";
    while (clock.elapsed() < 15000) {
        QFile answer(result);
        if (answer.open(QIODevice::ReadOnly)) {
            const QJsonObject reply = QJsonDocument::fromJson(answer.readAll()).object();
            answer.close();
            answer.remove();
            return reply;
        }
        QThread::msleep(100);
    }
    QFile::remove(inbox + "/" + name + ".json");
    return {{"ok", false}, {"error", "Fireteam didn't answer. Is it stuck behind a dialog?"}};
}

// Runs a request in the running app if there is one, otherwise directly.
QJsonObject run(const QJsonObject &request) {
    if (appRunning())
        return ask(request);
    if (Command::needsRunningApp(request.value("command").toString())
        || request.value("deploy").toBool())
        return {{"ok", false},
                {"error", "Fireteam isn't running. Start it with `fireteam open`, or `fireteam serve` for no window."}};
    Operations ops;
    return Command::execute(ops, request);
}

QString line(const QJsonObject &op) {
    return QString("%1  %2  %3  %4/%5  %6")
        .arg(op.value("id").toString(), op.value("codename").toString().leftJustified(18),
             op.value("status").toString().leftJustified(11))
        .arg(op.value("cyclesDone").toInt())
        .arg(op.value("cycles").toInt())
        .arg(op.value("directory").toString());
}

int report(const QJsonObject &result, bool json) {
    if (!result.value("ok").toBool())
        return fail(result.value("error").toString());
    if (json)
        out(QJsonDocument(result.value("op").toObject()).toJson());
    else
        out((line(result.value("op").toObject()) + "\n").toUtf8());
    return 0;
}

QJsonObject findSaved(const QString &query, QString *error) {
    // Matched the same way the app matches, on the saved data.
    const QString wanted = query.trimmed().toUpper().replace('-', ' ').replace('_', ' ');
    QJsonObject match;
    for (const auto &value : savedOperations()) {
        const QJsonObject op = value.toObject();
        if (op.value("id").toString().toUpper() == wanted || op.value("codename").toString() == wanted)
            return op;
        if (!wanted.isEmpty() && op.value("id").toString().toUpper().startsWith(wanted)) {
            if (!match.isEmpty()) {
                *error = QString("\"%1\" matches more than one operation.").arg(query);
                return {};
            }
            match = op;
        }
    }
    if (match.isEmpty())
        *error = QString("No operation matches \"%1\".").arg(query);
    return match;
}

QJsonObject detail(const QJsonObject &op) {
    QJsonObject view = op;
    const QString folder = dataDirectory() + "/ops/" + op.value("id").toString();
    view.insert("dossier", folder + "/dossier.html");
    // The last few lines of comms, for a quick read on what it's doing.
    QFile comms(folder + "/comms.jsonl");
    QJsonArray tail;
    if (comms.open(QIODevice::ReadOnly)) {
        const QList<QByteArray> lines = comms.readAll().split('\n');
        for (qsizetype i = qMax<qsizetype>(0, lines.size() - 16); i < lines.size(); ++i)
            if (!lines.at(i).trimmed().isEmpty())
                tail.append(QJsonDocument::fromJson(lines.at(i)).object());
    }
    view.insert("comms", tail);
    return view;
}

int show(const Arguments &arguments) {
    QString error;
    const QJsonObject op = findSaved(arguments.positional.value(1), &error);
    if (op.isEmpty())
        return fail(error);
    const QJsonObject view = detail(op);
    if (arguments.has("--json")) {
        out(QJsonDocument(view).toJson());
        return 0;
    }
    QString text = line(op) + "\n\nOBJECTIVE\n" + op.value("objective").toString() + "\n\nSITREP\n"
                   + (op.value("sitrep").toString().isEmpty() ? "None yet." : op.value("sitrep").toString()) + "\n";
    if (!op.value("requests").toArray().isEmpty()) {
        text += "\nAWAITING AUTHORISATION (approve in Fireteam with A)\n";
        for (const auto &request : op.value("requests").toArray())
            text += "  " + request.toObject().value("summary").toString() + "\n";
    }
    for (const auto &review : op.value("reviews").toArray())
        text += QString("\nOVERWATCH after cycle %1: %2. %3\n").arg(review.toObject().value("cycle").toInt())
                    .arg(review.toObject().value("grade").toString().toUpper(), review.toObject().value("summary").toString());
    text += "\nDEBRIEFS\n";
    for (const auto &path : op.value("reports").toArray())
        text += "  " + path.toString() + "\n";
    text += "\nCOMMS\n";
    for (const auto &value : view.value("comms").toArray())
        text += QString("  %1 %2 %3\n").arg(value.toObject().value("time").toString(),
                                              value.toObject().value("kind").toString().toUpper().leftJustified(7),
                                              value.toObject().value("text").toString().simplified().left(160));
    out(text.toUtf8());
    return 0;
}

int wait(const Arguments &arguments) {
    const int timeout = arguments.value("--timeout", "3600").toInt();
    QElapsedTimer clock;
    clock.start();
    while (true) {
        QString error;
        const QJsonObject op = findSaved(arguments.positional.value(1), &error);
        if (op.isEmpty())
            return fail(error);
        const QString status = op.value("status").toString();
        const bool moving = status == "deployed" || status == "staged";
        if (!moving || (timeout > 0 && clock.elapsed() > timeout * 1000LL)) {
            if (arguments.has("--json"))
                out(QJsonDocument(detail(op)).toJson());
            else
                out((line(op) + "\n" + op.value("sitrep").toString() + "\n").toUtf8());
            if (moving)
                return fail("Timed out while it was still working.");
            if (status == "complete")
                return 0;
            if (status == "failed" || status == "aborted")
                return 1;
            return 2;
        }
        QThread::msleep(2000);
    }
}

int installSkill() {
    QFile skill(":/skill/SKILL.md");
    if (!skill.open(QIODevice::ReadOnly))
        return fail("The skill isn't bundled in this build.");
    const QString path = QDir::homePath() + "/.claude/skills/fireteam/SKILL.md";
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return fail("Couldn't write " + path);
    file.write(skill.readAll());
    file.commit();
    out(QString("Installed %1\n").arg(path).toUtf8());
    return 0;
}

}

namespace Cli {

bool isCommand(const QByteArray &command) {
    return QList<QByteArray>{"list", "status", "show", "plan", "deploy", "order", "hold", "abort", "extract",
                             "discard", "wait", "skill", "help", "--help", "-h"}
        .contains(command);
}

int run(const QStringList &raw) {
    const Arguments arguments = parse(raw.mid(1));
    const QString command = arguments.positional.value(0);
    const bool json = arguments.has("--json");

    if (command == "help" || command.isEmpty() || arguments.has("--help")) {
        out(Usage);
        return 0;
    }
    if (command == "list" || command == "status") {
        const QJsonArray ops = savedOperations();
        if (json) {
            out(QJsonDocument(ops).toJson());
            return 0;
        }
        for (const auto &value : ops)
            out((line(value.toObject()) + "\n").toUtf8());
        return 0;
    }
    if (command == "show")
        return show(arguments);
    if (command == "wait")
        return wait(arguments);
    if (command == "skill")
        return arguments.positional.value(1) == "install" ? installSkill() : fail("Try `fireteam skill install`.");
    if (command == "plan") {
        if (!arguments.has("--dir") || !arguments.has("--objective"))
            return fail("plan needs --dir and --objective.");
        QJsonObject request{{"command", "plan"},
                            {"directory", QDir(arguments.value("--dir")).absolutePath()},
                            {"objective", arguments.value("--objective")},
                            {"codename", arguments.value("--codename")},
                            {"cycles", arguments.value("--cycles", "3").toInt()},
                            {"roe", arguments.value("--roe", "restricted")},
                            {"model", arguments.value("--model")},
                            {"handoffAt", arguments.value("--handoff", "250000").toInt()},
                            {"worktree", !arguments.has("--in-place")},
                            {"standing", arguments.value("--standing")},
                            {"overwatch", arguments.value("--overwatch", "off")},
                            {"deploy", arguments.has("--deploy")}};
        return report(::run(request), json);
    }
    if (QStringList{"deploy", "order", "hold", "abort", "extract", "discard"}.contains(command)) {
        if (arguments.positional.size() < 2)
            return fail(QString("%1 needs an operation.").arg(command));
        QJsonObject request{{"command", command}, {"op", arguments.positional.at(1)}};
        if (command == "order") {
            request.insert("text", arguments.positional.mid(2).join(' '));
            request.insert("deploy", arguments.has("--deploy"));
        }
        return report(::run(request), json);
    }
    std::fputs(Usage, stderr);
    return 1;
}

}
