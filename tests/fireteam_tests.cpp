#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QProcess>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>

#include "command.h"
#include "mcpserver.h"
#include "operations.h"
#include "stream.h"
#include "theme.h"
#include "translator.h"

// A stand-in for claude: prints a stream-json session, records its arguments,
// and writes the debrief the prompt asks for on the first cycle only, so both
// the agent's own report and Fireteam's fallback are exercised. When the
// FIRETEAM_TEST_STALL file exists, one run reports a huge context and then
// hangs, the way a runaway cycle would.
// The script lives in tests/fakeclaude.sh, compiled in as a resource.
static QByteArray fakeClaudeScript() {
    QFile file(":/fakeclaude.sh");
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
}

class FireteamTests : public QObject {
    Q_OBJECT

private slots:
    void parsesStreamEvents()
    {
        auto events = Stream::parseLine(R"({"type":"system","subtype":"init","session_id":"abc","model":"m"})");
        QCOMPARE(events.size(), 1);
        QCOMPARE(events.first().kind, StreamEvent::Session);
        QCOMPARE(events.first().sessionId, QString("abc"));

        events = Stream::parseLine(R"({"type":"assistant","message":{"content":[{"type":"text","text":"hi"},{"type":"tool_use","name":"Bash","input":{"command":"make test"}}]}})");
        QCOMPARE(events.size(), 2);
        QCOMPARE(events.at(0).text, QString("hi"));
        QCOMPARE(events.at(1).kind, StreamEvent::Tool);
        QCOMPARE(events.at(1).text, QString("Bash  make test"));

        events = Stream::parseLine(R"({"type":"result","subtype":"error_max_turns","is_error":true,"total_cost_usd":1.5})");
        QCOMPARE(events.first().kind, StreamEvent::Result);
        QVERIFY(events.first().isError);
        QCOMPARE(events.first().costUsd, 1.5);

        QCOMPARE(Stream::parseLine("not json").first().kind, StreamEvent::Error);
        QVERIFY(Stream::parseLine("").isEmpty());
    }

    void promptNamesTheCycleAndReport()
    {
        const QString first = Stream::cyclePrompt("IRON VIPER", "Ship it", 1, 3, "/r/cycle-01.html");
        QVERIFY(first.contains("CYCLE 1 OF 3"));
        QVERIFY(first.contains("/r/cycle-01.html"));
        QVERIFY(first.contains("first cycle"));
        QVERIFY(Stream::cyclePrompt("X", "Y", 3, 3, "r").contains("final cycle"));
    }

    void fallbackReportEscapes()
    {
        const QString html = Stream::fallbackReport("<b>", 1, 2, "a & b", "done", {"Edit x"}, {});
        QVERIFY(html.contains("&lt;b&gt;"));
        QVERIFY(html.contains("a &amp; b"));
        QVERIFY(!html.contains("<b>"));
    }

    void refusesBadPlans()
    {
        QTemporaryDir data;
        Operations ops(data.path(), "/bin/true");
        QVERIFY(!ops.validate("/no/such/dir", "x").isEmpty());
        QVERIFY(!ops.validate(data.path(), "  ").isEmpty());
        QVERIFY(ops.validate(data.path(), "build it").isEmpty());
        QCOMPARE(ops.create("", "/no/such/dir", "x", 1, "restricted", ""), -1);
        QCOMPARE(ops.rowCount(), 0);
    }

    void runsCyclesAndFilesDebriefs()
    {
        QTemporaryDir data, project, bin;
        const QString claude = bin.filePath("claude"), log = bin.filePath("args.log");
        write(claude, fakeClaudeScript());
        QVERIFY(QFile::setPermissions(claude, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
        qputenv("FIRETEAM_TEST_LOG", log.toUtf8());

        Operations ops(data.path(), claude);
        QCOMPARE(ops.create("iron viper", project.path(), "Build the thing", 2, "restricted", "sonnet"), 0);
        QCOMPARE(ops.at(0).codename, QString("IRON VIPER"));

        QSignalSpy finished(&ops, &Operations::operationFinished);
        ops.deploy(0);
        QCOMPARE(ops.deployedCount(), 1);
        QVERIFY(finished.wait(10000));

        const Operation &op = ops.at(0);
        QCOMPARE(op.status, QString("complete"));
        QCOMPARE(op.cyclesDone, 2);
        QCOMPARE(op.sessionId, QString("sess-1"));
        QCOMPARE(op.costUsd, 0.5);
        QCOMPARE(op.reports.size(), 2);
        QCOMPARE(read(op.reports.at(0)), QByteArray("<html>agent debrief</html>\n"));
        QVERIFY(read(op.reports.at(1)).contains("Fireteam wrote this one"));
        QVERIFY(read(ops.dossierPath(op)).contains("debriefs/cycle-02.html"));
        QCOMPARE(ops.deployedCount(), 0);

        // The second cycle resumes the first cycle's session, in the project.
        const QStringList runs = QString::fromUtf8(read(log)).split("---\n", Qt::SkipEmptyParts);
        QCOMPARE(runs.size(), 2);
        QVERIFY(!runs.at(0).contains("--resume"));
        QVERIFY(runs.at(1).contains("--resume\nsess-1"));
        QVERIFY(runs.at(0).contains("--permission-mode\nacceptEdits"));
        QVERIFY(runs.at(0).contains("--model\nsonnet"));
    }

    void handsOffPastTheContextLine()
    {
        QTemporaryDir data, project, bin;
        const QString claude = bin.filePath("claude"), log = bin.filePath("args.log");
        write(claude, fakeClaudeScript());
        QVERIFY(QFile::setPermissions(claude, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
        qputenv("FIRETEAM_TEST_LOG", log.toUtf8());
        qputenv("FIRETEAM_TEST_CONTEXT", "6000");

        Operations ops(data.path(), claude);
        QCOMPARE(ops.create("", project.path(), "Build", 3, "restricted", "", 5000), 0);
        QSignalSpy finished(&ops, &Operations::operationFinished);
        ops.deploy(0);
        QVERIFY(finished.wait(10000));
        qunsetenv("FIRETEAM_TEST_CONTEXT");

        const Operation &op = ops.at(0);
        QCOMPARE(op.status, QString("complete"));
        QCOMPARE(op.cyclesDone, 3);
        QCOMPARE(op.session, 3);
        QCOMPARE(op.handoffs.size(), 2);
        QCOMPARE(op.contextTokens, 6000);
        QCOMPARE(op.sitrep, QString("Cycle done."));

        // Cycle, hand-off, fresh cycle, hand-off, fresh cycle. The hand-off
        // resumes the old session; the cycle after it starts a new one and is
        // pointed at the brief.
        const QStringList runs = QString::fromUtf8(read(log)).split("---\n", Qt::SkipEmptyParts);
        QCOMPARE(runs.size(), 5);
        QVERIFY(runs.at(1).contains("HANDOFF") && runs.at(1).contains("--resume\nsess-1"));
        QVERIFY(!runs.at(2).contains("--resume"));
        QVERIFY(runs.at(2).contains("handoffs/session-01.md"));
        QVERIFY(runs.at(4).contains("handoffs/session-02.md"));
    }

    void neverHandsOffWhenDisabled()
    {
        QTemporaryDir data, project, bin;
        const QString claude = bin.filePath("claude");
        write(claude, fakeClaudeScript());
        QVERIFY(QFile::setPermissions(claude, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
        qputenv("FIRETEAM_TEST_LOG", bin.filePath("args.log").toUtf8());
        qputenv("FIRETEAM_TEST_CONTEXT", "900000");

        Operations ops(data.path(), claude);
        QCOMPARE(ops.create("", project.path(), "Build", 2, "restricted", "", 0), 0);
        QSignalSpy finished(&ops, &Operations::operationFinished);
        ops.deploy(0);
        QVERIFY(finished.wait(10000));
        qunsetenv("FIRETEAM_TEST_CONTEXT");
        QCOMPARE(ops.at(0).session, 1);
        QVERIFY(ops.at(0).handoffs.isEmpty());
    }

    void ordersGoOutWithTheNextCycle()
    {
        QTemporaryDir data, project, bin;
        const QString claude = fakeClaude(bin), log = bin.filePath("args.log");
        qputenv("FIRETEAM_TEST_LOG", log.toUtf8());

        Operations ops(data.path(), claude);
        QCOMPARE(ops.create("", project.path(), "Build", 2, "restricted", ""), 0);
        QSignalSpy finished(&ops, &Operations::operationFinished);
        QSignalSpy alerts(&ops, &Operations::alert);
        ops.sendOrders(0, "Use SQLite, not JSON files.", true);
        QCOMPARE(ops.at(0).status, QString("deployed"));
        QVERIFY(ops.at(0).orders.isEmpty());
        QVERIFY(finished.wait(10000));

        // The orders ride with the first cycle only, and the board hears about
        // each finished cycle.
        const QStringList runs = QString::fromUtf8(read(log)).split("---\n", Qt::SkipEmptyParts);
        QCOMPARE(runs.size(), 2);
        QVERIFY(runs.at(0).contains("ORDERS FROM COMMAND") && runs.at(0).contains("Use SQLite, not JSON files."));
        QVERIFY(!runs.at(1).contains("ORDERS FROM COMMAND"));
        QCOMPARE(alerts.size(), 2);

        // Orders to a finished operation wait for the next deploy unless sent
        // with it.
        ops.sendOrders(0, "Add a README.", false);
        QCOMPARE(ops.at(0).status, QString("complete"));
        QCOMPARE(ops.at(0).orders, QStringList{"Add a README."});
        ops.clearOrders(0);
        QVERIFY(ops.at(0).orders.isEmpty());
    }

    void keepsOrdersFromAFailedCycle()
    {
        QTemporaryDir data, project;
        Operations ops(data.path(), "/bin/true");
        QCOMPARE(ops.create("", project.path(), "Build", 1, "restricted", ""), 0);
        QSignalSpy finished(&ops, &Operations::operationFinished);
        ops.sendOrders(0, "Add a README.", true);
        QVERIFY(finished.wait(5000));
        QCOMPARE(ops.at(0).status, QString("failed"));
        QCOMPARE(ops.at(0).orders, QStringList{"Add a README."});
    }

    void snapshotsEachCycleAndRollsBack()
    {
        QTemporaryDir data, project, bin;
        const QString claude = fakeClaude(bin);
        qputenv("FIRETEAM_TEST_LOG", bin.filePath("args.log").toUtf8());
        QVERIFY(gitIn(project.path(), {"init", "-q"}));
        write(project.filePath("app.txt"), "app\n");

        Operations ops(data.path(), claude);
        QCOMPARE(ops.create("", project.path(), "Build", 2, "restricted", ""), 0);
        QSignalSpy finished(&ops, &Operations::operationFinished);
        ops.deploy(0);
        QVERIFY(finished.wait(15000));

        const Operation &op = ops.at(0);
        QCOMPARE(op.history.size(), 2);
        const QVariantMap first = op.history.at(0).toMap();
        QCOMPARE(first.value("cycle").toInt(), 1);
        QCOMPARE(first.value("outcome").toString(), QString("complete"));
        QCOMPARE(first.value("files").toInt(), 1);
        QCOMPARE(first.value("added").toInt(), 1);
        const QVariantList changes = ops.cycleChanges(0, 1);
        QCOMPARE(changes.size(), 1);
        QCOMPARE(changes.first().toMap().value("path").toString(), QString("notes.txt"));
        QCOMPARE(changes.first().toMap().value("status").toString(), QString("M"));
        QVERIFY(ops.cycleDiff(0, 1, "notes.txt").contains("+line"));

        // The user's index and branches never saw the snapshots.
        QCOMPARE(gitOut(project.path(), {"status", "--porcelain"}), QString("?? app.txt\n?? notes.txt\n"));
        QVERIFY(gitOut(project.path(), {"for-each-ref", "refs/fireteam/"}).contains("run-2-after"));

        // Back to before cycle 1: the agent's file goes, the user's stays.
        QVERIFY(ops.rollback(0, 0));
        QVERIFY(!QFile::exists(project.filePath("notes.txt")));
        QCOMPARE(read(project.filePath("app.txt")), QByteArray("app\n"));
        QVERIFY(ops.undoRollback(0));
        QCOMPARE(read(project.filePath("notes.txt")), QByteArray("line\nline\n"));
        QVERIFY(!ops.undoRollback(0));

        ops.remove(0);
        QCOMPARE(gitOut(project.path(), {"for-each-ref", "refs/fireteam/"}), QString());
    }

    void keepsHistoryWithoutGit()
    {
        QTemporaryDir data, project, bin;
        const QString claude = fakeClaude(bin);
        qputenv("FIRETEAM_TEST_LOG", bin.filePath("args.log").toUtf8());
        Operations ops(data.path(), claude);
        QCOMPARE(ops.create("", project.path(), "Build", 1, "restricted", ""), 0);
        QSignalSpy finished(&ops, &Operations::operationFinished);
        ops.deploy(0);
        QVERIFY(finished.wait(10000));
        QCOMPARE(ops.at(0).history.size(), 1);
        QVERIFY(ops.at(0).history.first().toMap().value("before").toString().isEmpty());
        QVERIFY(ops.cycleChanges(0, 0).isEmpty());
        QVERIFY(!ops.rollback(0, 0));
    }

    void holdsAfterTheCurrentCycle()
    {
        QTemporaryDir data, project, bin;
        const QString claude = fakeClaude(bin), log = bin.filePath("args.log");
        qputenv("FIRETEAM_TEST_LOG", log.toUtf8());

        Operations ops(data.path(), claude);
        QCOMPARE(ops.create("", project.path(), "Build", 3, "restricted", ""), 0);
        QSignalSpy finished(&ops, &Operations::operationFinished);
        ops.deploy(0);
        ops.setHold(0, true);
        QVERIFY(finished.wait(10000));
        QCOMPARE(ops.at(0).status, QString("held"));
        QCOMPARE(ops.at(0).cyclesDone, 1);
        QVERIFY(!ops.at(0).hold);
        QCOMPARE(ops.deployedCount(), 0);

        ops.deploy(0);
        QVERIFY(finished.wait(10000));
        QCOMPARE(ops.at(0).status, QString("complete"));
        QCOMPARE(ops.at(0).cyclesDone, 3);
    }

    void handsOffMidCycleAtTheCeiling()
    {
        QTemporaryDir data, project, bin;
        const QString claude = fakeClaude(bin), log = bin.filePath("args.log");
        const QString stall = bin.filePath("stall");
        write(stall, "");
        qputenv("FIRETEAM_TEST_LOG", log.toUtf8());
        qputenv("FIRETEAM_TEST_STALL", stall.toUtf8());

        Operations ops(data.path(), claude);
        QCOMPARE(ops.create("", project.path(), "Build", 1, "restricted", "", 5000), 0);
        QCOMPARE(Operations::ceiling(ops.at(0)), 10000);
        QSignalSpy finished(&ops, &Operations::operationFinished);
        ops.deploy(0);
        QVERIFY(finished.wait(15000));
        qunsetenv("FIRETEAM_TEST_STALL");

        // Stopped mid-cycle, briefed, and the same cycle finished by a fresh
        // session.
        const Operation &op = ops.at(0);
        QCOMPARE(op.status, QString("complete"));
        QCOMPARE(op.cyclesDone, 1);
        QCOMPARE(op.session, 2);
        QCOMPARE(op.handoffs.size(), 1);
        const QStringList runs = QString::fromUtf8(read(log)).split("---\n", Qt::SkipEmptyParts);
        QCOMPARE(runs.size(), 3);
        QVERIFY(runs.at(1).contains("stopped part-way through cycle 1"));
        QVERIFY(runs.at(1).contains("--resume\nsess-1"));
        QVERIFY(!runs.at(2).contains("--resume"));
        QVERIFY(runs.at(2).contains("CYCLE 1 OF 1") && runs.at(2).contains("handoffs/session-01.md"));
    }

    void amendsABriefing()
    {
        QTemporaryDir data, project, bin;
        const QString claude = fakeClaude(bin);
        qputenv("FIRETEAM_TEST_LOG", bin.filePath("args.log").toUtf8());

        Operations ops(data.path(), claude);
        QCOMPARE(ops.create("", project.path(), "Build", 1, "restricted", ""), 0);
        QSignalSpy finished(&ops, &Operations::operationFinished);
        ops.deploy(0);
        QVERIFY(!ops.update(0, "", "Changed mid-flight", 1, "free", "", 0));
        QVERIFY(finished.wait(10000));

        QVERIFY(!ops.update(0, "", "  ", 2, "free", "", 0));
        QVERIFY(ops.update(0, "red fox", "Build, then document", 0, "free", "haiku", 400000));
        const Operation &op = ops.at(0);
        QCOMPARE(op.codename, QString("RED FOX"));
        QCOMPARE(op.cycles, 1);
        QCOMPARE(op.status, QString("complete"));
        QCOMPARE(op.roe, QString("free"));
        QCOMPARE(op.handoffAt, 400000);
        QVERIFY(ops.update(0, "", "Build, then document", 3, "free", "haiku", 400000));
        QCOMPARE(ops.at(0).cycles, 3);
        QCOMPARE(ops.at(0).status, QString("standby"));
    }

    void foldsTheClosingMessageIntoTheSitrep()
    {
        QTemporaryDir data, project, bin;
        const QString claude = bin.filePath("claude");
        write(claude, "#!/bin/sh\n"
                      "echo '{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"All done.\"}]}}'\n"
                      "echo '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"result\":\"All done.\"}'\n");
        QFile::setPermissions(claude, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        {
            Operations ops(data.path(), claude);
            QCOMPARE(ops.create("", project.path(), "Build", 1, "restricted", ""), 0);
            QSignalSpy finished(&ops, &Operations::operationFinished);
            ops.deploy(0);
            QVERIFY(finished.wait(10000));
            int says = 0, results = 0;
            for (const QVariant &line : ops.at(0).comms) {
                says += line.toMap().value("kind") == "say";
                results += line.toMap().value("kind") == "result";
            }
            QCOMPARE(says, 0);
            QCOMPARE(results, 1);
            QVERIFY(ops.at(0).events > 0);
        }
        // The same holds when the comms are read back from disk.
        Operations reloaded(data.path(), claude);
        int says = 0;
        for (const QVariant &line : reloaded.at(0).comms)
            says += line.toMap().value("kind") == "say";
        QCOMPARE(says, 0);
    }

    void suggestsRulesForRefusals()
    {
        auto events = Stream::parseLine(R"({"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t9","is_error":true,"content":"This command requires approval"}]}})");
        QCOMPARE(events.size(), 1);
        QCOMPARE(events.first().kind, StreamEvent::Denied);
        QCOMPARE(events.first().toolId, QString("t9"));
        events = Stream::parseLine(R"({"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t9","is_error":true,"content":"exit code 1"}]}})");
        QVERIFY(events.isEmpty());
        events = Stream::parseLine(R"({"type":"result","subtype":"success","result":"x","permission_denials":[{"tool_name":"Bash","tool_input":{"command":"make"}}]})");
        QCOMPARE(events.first().denials.size(), 1);

        using Choices = QList<QStringList>;
        auto bash = [](const QString &command) { return Stream::rulesFor("Bash", {{"command", command}}); };
        QCOMPARE(bash("npm test"), (Choices{{"Bash(npm test:*)"}}));
        QCOMPARE(bash("npm test -- --watch"), (Choices{{"Bash(npm test:*)"}, {"Bash(npm test -- --watch)"}}));
        QCOMPARE(bash("node src/cli.js Ada"), (Choices{{"Bash(node src/cli.js:*)"}, {"Bash(node src/cli.js Ada)"}}));
        QCOMPARE(bash("git -C . rev-parse HEAD"), (Choices{{"Bash(git -C . rev-parse:*)"}, {"Bash(git -C . rev-parse HEAD)"}}));
        QCOMPARE(bash("CI=1 make check"), (Choices{{"Bash(make check:*)"}, {"Bash(CI=1 make check)"}}));
        // A chain is approved part by part, without the parts that only read.
        QCOMPARE(bash("npm test; echo \"exit=$?\"; cat log.txt; git -C . rev-parse | head -1"), (Choices{{"Bash(npm test:*)"}}));
        QCOMPARE(bash("cd app && npm install && npm run build"), (Choices{{"Bash(npm install:*)", "Bash(npm run build:*)"}}));
        QCOMPARE(Stream::rulesFor("WebFetch", {{"url", "https://docs.example.com/a"}}), (Choices{{"WebFetch(domain:docs.example.com)"}}));
        QCOMPARE(Stream::ruleFromText("npm test"), QString("Bash(npm test:*)"));
        QCOMPARE(Stream::ruleFromText("Bash(make)"), QString("Bash(make)"));
        QCOMPARE(Stream::ruleFromText("WebSearch"), QString("WebSearch"));
        QCOMPARE(Stream::describeRule("Bash(npm test:*)"), QString("npm test …"));
    }

    void holdsForAuthorisationAndPassesApprovals()
    {
        QTemporaryDir data, project, bin;
        const QString claude = fakeClaude(bin), log = bin.filePath("args.log");
        qputenv("FIRETEAM_TEST_LOG", log.toUtf8());
        qputenv("FIRETEAM_TEST_DENY", "1");

        Operations ops(data.path(), claude);
        QCOMPARE(ops.create("", project.path(), "Test it", 3, "restricted", ""), 0);
        QSignalSpy finished(&ops, &Operations::operationFinished);
        QSignalSpy alerts(&ops, &Operations::alert);
        ops.deploy(0);
        QVERIFY(finished.wait(10000));

        // Seen live and in the result, but asked about once; and the op holds
        // rather than running into it again.
        QCOMPARE(ops.at(0).requests.size(), 1);
        QCOMPARE(ops.at(0).requests.first().toMap().value("summary").toString(), QString("Bash  npm test"));
        QCOMPARE(ops.at(0).status, QString("held"));
        QCOMPARE(ops.at(0).cyclesDone, 1);
        QVERIFY(alerts.size() >= 2);

        QVERIFY(ops.approve(0, 0, 0, true));
        QVERIFY(ops.at(0).requests.isEmpty());
        QCOMPARE(ops.at(0).allowed, QStringList{"Bash(npm test:*)"});
        QCOMPARE(ops.at(0).orders.size(), 1);
        QVERIFY(ops.at(0).orders.first().contains("`npm test …`"));
        const QJsonObject settings = QJsonDocument::fromJson(read(project.filePath(".claude/settings.local.json"))).object();
        QCOMPARE(settings.value("permissions").toObject().value("allow").toArray().first().toString(), QString("Bash(npm test:*)"));

        ops.deploy(0);
        QVERIFY(finished.wait(10000));
        qunsetenv("FIRETEAM_TEST_DENY");
        QCOMPARE(ops.at(0).status, QString("complete"));
        const QStringList runs = QString::fromUtf8(read(log)).split("---\n", Qt::SkipEmptyParts);
        QVERIFY(runs.at(1).contains("--allowedTools\nBash(npm test:*)\n"));
        QVERIFY(runs.at(1).contains("authorised `npm test …`"));
        // Refused again although approved: reported, not asked again.
        QVERIFY(ops.at(0).requests.isEmpty());

        // Denying queues an order instead; a typed command becomes a rule;
        // and a rule can be withdrawn.
        ops.revoke(0, "Bash(npm test:*)");
        QVERIFY(ops.at(0).allowed.isEmpty());
        QVERIFY(ops.allow(0, "make check", false));
        QCOMPARE(ops.at(0).allowed, QStringList{"Bash(make check:*)"});
    }

    void queuesPastTheSquadLimit()
    {
        QTemporaryDir data, one, two, bin;
        const QString claude = fakeClaude(bin);
        qputenv("FIRETEAM_TEST_LOG", bin.filePath("args.log").toUtf8());
        qputenv("FIRETEAM_TEST_SLOW", "0.3");
        Operations ops(data.path(), claude);
        ops.setMaxDeployed(1);
        QCOMPARE(ops.create("", one.path(), "One", 1, "restricted", ""), 0);
        QCOMPARE(ops.create("", two.path(), "Two", 1, "restricted", ""), 0);
        QSignalSpy finished(&ops, &Operations::operationFinished);
        ops.deploy(0);
        ops.deploy(1);
        QCOMPARE(ops.deployedCount(), 1);
        QCOMPARE(ops.at(1).status, QString("staged"));
        QCOMPARE(ops.stagedCount(), 1);
        QTRY_COMPARE_WITH_TIMEOUT(finished.size(), 2, 15000);
        qunsetenv("FIRETEAM_TEST_SLOW");
        QCOMPARE(ops.at(0).status, QString("complete"));
        QCOMPARE(ops.at(1).status, QString("complete"));

        // The limit is kept for next time.
        Operations reloaded(data.path(), claude);
        QCOMPARE(reloaded.maxDeployed(), 1);
    }

    void takesTurnsInOneDirectory()
    {
        QTemporaryDir data, project, bin;
        const QString claude = fakeClaude(bin);
        qputenv("FIRETEAM_TEST_LOG", bin.filePath("args.log").toUtf8());
        qputenv("FIRETEAM_TEST_SLOW", "0.3");
        Operations ops(data.path(), claude);
        ops.setMaxDeployed(0);
        QCOMPARE(ops.create("", project.path(), "One", 1, "restricted", ""), 0);
        QCOMPARE(ops.create("", project.path(), "Two", 1, "restricted", ""), 0);
        QCOMPARE(ops.sharing(project.path()).size(), 2);
        QSignalSpy finished(&ops, &Operations::operationFinished);
        ops.deploy(0);
        ops.deploy(1);
        QCOMPARE(ops.at(1).status, QString("staged"));
        QVERIFY(ops.at(1).comms.last().toMap().value("text").toString().contains("same directory"));
        QTRY_COMPARE_WITH_TIMEOUT(finished.size(), 2, 15000);
        qunsetenv("FIRETEAM_TEST_SLOW");
        QCOMPARE(ops.at(1).status, QString("complete"));
    }

    void worksInAWorktreeAndExtracts()
    {
        QTemporaryDir data, project, bin;
        const QString claude = fakeClaude(bin), log = bin.filePath("args.log");
        qputenv("FIRETEAM_TEST_LOG", log.toUtf8());
        QVERIFY(gitIn(project.path(), {"init", "-q", "-b", "main"}));
        write(project.filePath("app.txt"), "app\n");
        QVERIFY(gitIn(project.path(), {"add", "-A"}));
        QVERIFY(gitIn(project.path(), {"-c", "user.name=T", "-c", "user.email=t@x", "commit", "-q", "-m", "start"}));

        Operations ops(data.path(), claude);
        QCOMPARE(ops.repository(project.path()).value("commits").toBool(), true);
        QCOMPARE(ops.create("red fox", project.path(), "Build", 2, "restricted", "", 250000, true), 0);
        QSignalSpy finished(&ops, &Operations::operationFinished);
        ops.deploy(0);
        QVERIFY(finished.wait(15000));
        const Operation &op = ops.at(0);
        QCOMPARE(op.status, QString("complete"));
        QVERIFY(op.branch.startsWith("fireteam/red-fox-"));
        QCOMPARE(op.baseBranch, QString("main"));
        // The agent worked in the worktree; the project is untouched.
        QVERIFY(QFile::exists(op.workdir + "/notes.txt"));
        QVERIFY(!QFile::exists(project.filePath("notes.txt")));
        QCOMPARE(gitOut(project.path(), {"status", "--porcelain"}), QString());
        // Both cycles ran there, the second resuming the first's session.
        const QStringList runs = QString::fromUtf8(read(log)).split("---\n", Qt::SkipEmptyParts);
        QVERIFY(runs.at(1).contains("--resume\nsess-1"));
        QCOMPARE(ops.worktreeSummary(0).value("files").toInt(), 1);

        QVERIFY(ops.extract(0));
        QCOMPARE(read(project.filePath("notes.txt")), QByteArray("line\nline\n"));
        QCOMPARE(gitOut(project.path(), {"status", "--porcelain"}), QString());
        QVERIFY(gitOut(project.path(), {"log", "--oneline"}).contains("Extract RED FOX"));
        QVERIFY(gitOut(project.path(), {"branch", "--list", "fireteam/*"}).isEmpty());
        QVERIFY(ops.at(0).workdir.isEmpty());

        // Next time: a fresh worktree from the merged work, at the same path,
        // so the session carries on.
        ops.deploy(0);
        QVERIFY(finished.wait(15000));
        QVERIFY(QFile::exists(ops.at(0).workdir + "/notes.txt"));
        QVERIFY(QString::fromUtf8(read(log)).split("---\n", Qt::SkipEmptyParts).last().contains("--resume\nsess-1"));

        // A conflict is reported and undone, never forced.
        write(project.filePath("notes.txt"), "mine\n");
        QVERIFY(gitIn(project.path(), {"-c", "user.name=T", "-c", "user.email=t@x", "commit", "-qam", "mine"}));
        QVERIFY(!ops.extract(0));
        QVERIFY(ops.at(0).comms.last().toMap().value("text").toString().contains("notes.txt"));
        QCOMPARE(gitOut(project.path(), {"status", "--porcelain"}), QString());
        QCOMPARE(read(project.filePath("notes.txt")), QByteArray("mine\n"));
        QVERIFY(ops.discard(0));
        QVERIFY(gitOut(project.path(), {"branch", "--list", "fireteam/*"}).isEmpty());
    }

    void startsAFreshSessionWhenMovedIntoAWorktree()
    {
        QTemporaryDir data, project, bin;
        const QString claude = fakeClaude(bin), log = bin.filePath("args.log");
        qputenv("FIRETEAM_TEST_LOG", log.toUtf8());
        QVERIFY(gitIn(project.path(), {"init", "-q"}));
        write(project.filePath("app.txt"), "app\n");
        QVERIFY(gitIn(project.path(), {"add", "-A"}));
        QVERIFY(gitIn(project.path(), {"-c", "user.name=T", "-c", "user.email=t@x", "commit", "-q", "-m", "start"}));
        Operations ops(data.path(), claude);
        QCOMPARE(ops.create("", project.path(), "Build", 1, "restricted", ""), 0);
        QSignalSpy finished(&ops, &Operations::operationFinished);
        ops.deploy(0);
        QVERIFY(finished.wait(10000));
        QVERIFY(ops.update(0, "", "Build", 2, "restricted", "", 250000, true, "Keep it small."));
        ops.deploy(0);
        QVERIFY(finished.wait(10000));
        const QString last = QString::fromUtf8(read(log)).split("---\n", Qt::SkipEmptyParts).last();
        QVERIFY(!last.contains("--resume"));
        QVERIFY(last.contains("HANDOFF") && last.contains("debriefs/cycle-01.html"));
        QVERIFY(last.contains("STANDING ORDERS") && last.contains("Keep it small."));
        QCOMPARE(ops.at(0).session, 2);
    }

    void pinsDownAtTheUsageLimitAndResumes()
    {
        QTemporaryDir data, project, bin;
        const QString claude = fakeClaude(bin), limit = bin.filePath("limit");
        write(limit, "");
        qputenv("FIRETEAM_TEST_LOG", bin.filePath("args.log").toUtf8());
        qputenv("FIRETEAM_TEST_LIMIT", limit.toUtf8());
        qputenv("FIRETEAM_PIN_MARGIN", "0");
        Operations ops(data.path(), claude);
        QCOMPARE(ops.create("", project.path(), "Build", 1, "restricted", ""), 0);
        QSignalSpy finished(&ops, &Operations::operationFinished);
        ops.deploy(0);
        QVERIFY(finished.wait(10000));
        QCOMPARE(ops.at(0).status, QString("pinned"));
        QCOMPARE(ops.at(0).cyclesDone, 0);
        QCOMPARE(ops.usage().value("status").toString(), QString("rejected"));
        // After the reset it picks the same cycle up on its own.
        QTRY_COMPARE_WITH_TIMEOUT(ops.at(0).status, QString("complete"), 15000);
        qunsetenv("FIRETEAM_TEST_LIMIT");
        qunsetenv("FIRETEAM_PIN_MARGIN");
        QCOMPARE(ops.at(0).cyclesDone, 1);
        QCOMPARE(ops.at(0).history.first().toMap().value("outcome").toString(), QString("pinned"));
    }

    void keepsAServiceRecord()
    {
        QTemporaryDir data, project, bin;
        const QString claude = fakeClaude(bin);
        qputenv("FIRETEAM_TEST_LOG", bin.filePath("args.log").toUtf8());
        QVERIFY(gitIn(project.path(), {"init", "-q"}));
        Operations ops(data.path(), claude);
        QCOMPARE(ops.create("", project.path(), "Build", 2, "restricted", ""), 0);
        QSignalSpy finished(&ops, &Operations::operationFinished);
        ops.deploy(0);
        QVERIFY(finished.wait(15000));
        const QVariantMap record = ops.serviceRecord();
        QCOMPARE(record.value("operations").toInt(), 1);
        QCOMPARE(record.value("runs").toInt(), 2);
        QCOMPARE(record.value("successRate").toDouble(), 1.0);
        QCOMPARE(record.value("added").toInt(), 2);
        QCOMPARE(record.value("cost").toDouble(), 0.5);
        const QVariantList weeks = record.value("weeks").toList();
        QCOMPARE(weeks.size(), 8);
        QCOMPARE(weeks.last().toMap().value("cycles").toInt(), 2);
        QCOMPARE(weeks.last().toMap().value("cost").toDouble(), 0.5);
        QCOMPARE(record.value("projects").toList().first().toMap().value("runs").toInt(), 2);
    }

    void runsCommandLineRequests()
    {
        QTemporaryDir data, project;
        Operations ops(data.path(), "/bin/true");
        QJsonObject result = Command::execute(ops, {{"command", "plan"}, {"directory", "/no/such"}, {"objective", "x"}});
        QVERIFY(!result.value("ok").toBool());
        result = Command::execute(ops, {{"command", "plan"}, {"directory", project.path()}, {"objective", "Build"},
                                        {"codename", "red fox"}, {"cycles", 2}, {"overwatch", "review"}});
        QVERIFY(result.value("ok").toBool());
        QCOMPARE(result.value("op").toObject().value("codename").toString(), QString("RED FOX"));
        QCOMPARE(ops.at(0).overwatch, QString("review"));
        QCOMPARE(ops.find("red-fox"), 0);
        QCOMPARE(ops.find(ops.at(0).id.left(3)), 0);
        QCOMPARE(ops.find("blue"), -1);
        result = Command::execute(ops, {{"command", "order"}, {"op", "Red Fox"}, {"text", "Add tests."}});
        QVERIFY(result.value("ok").toBool());
        QCOMPARE(ops.at(0).orders, QStringList{"Add tests."});
        QVERIFY(!Command::execute(ops, {{"command", "hold"}, {"op", "red-fox"}}).value("ok").toBool());
        QVERIFY(!Command::execute(ops, {{"command", "fly"}, {"op", "red-fox"}}).value("ok").toBool());
        QVERIFY(Command::needsRunningApp("deploy") && !Command::needsRunningApp("order"));
    }

    void bridgesTheFieldLink()
    {
        QTemporaryDir data, project;
        Operations ops(data.path(), "/bin/true");
        QCOMPARE(ops.create("", project.path(), "Build", 1, "supervised", ""), 0);
        QCOMPARE(ops.at(0).roe, QString("supervised"));
        McpServer server(ops.at(0).id, ops.fieldLinkName());
        QList<QJsonObject> sent;
        connect(&server, &McpServer::send, [&](const QByteArray &line) { sent << QJsonDocument::fromJson(line).object(); });
        auto call = [&](int id, const QString &method, const QJsonObject &params = {}) {
            server.receive(QJsonDocument(QJsonObject{{"jsonrpc", "2.0"}, {"id", id}, {"method", method}, {"params", params}})
                               .toJson(QJsonDocument::Compact));
        };
        auto text = [](const QJsonObject &reply) {
            return reply.value("result").toObject().value("content").toArray().first().toObject().value("text").toString();
        };

        call(1, "initialize", {{"protocolVersion", "2025-06-18"}});
        QCOMPARE(sent.last().value("result").toObject().value("protocolVersion").toString(), QString("2025-06-18"));
        call(2, "tools/list");
        QCOMPARE(sent.last().value("result").toObject().value("tools").toArray().size(), 3);

        // Progress reaches the board.
        QJsonObject progress;
        progress.insert("status", "Router done");
        progress.insert("progress", 40);
        call(3, "tools/call", {{"name", "sitrep"}, {"arguments", progress}});
        QTRY_COMPARE(ops.at(0).progress, 40);
        QCOMPARE(ops.at(0).progressNote, QString("Router done"));

        // A question waits for the operator.
        const int before = sent.size();
        QJsonObject question;
        question.insert("question", "SQLite or JSON?");
        question.insert("options", QJsonArray{"SQLite", "JSON"});
        call(4, "tools/call", {{"name", "request_orders"}, {"arguments", question}});
        QTRY_COMPARE(ops.at(0).questions.size(), 1);
        QCOMPARE(sent.size(), before);
        QVERIFY(ops.answer(0, ops.at(0).questions.first().toMap().value("id").toString(), "SQLite"));
        QTRY_COMPARE(sent.size(), before + 1);
        QCOMPARE(sent.last().value("id").toInt(), 4);
        QCOMPARE(text(sent.last()), QString("SQLite"));

        // A permission prompt, approved for good, then cleared without asking.
        const QJsonObject npm{{"tool_name", "Bash"}, {"input", QJsonObject{{"command", "npm test"}}}};
        call(5, "tools/call", {{"name", "authorise"}, {"arguments", npm}});
        QTRY_COMPARE(ops.at(0).prompts.size(), 1);
        QVERIFY(ops.decide(0, ops.at(0).prompts.first().toMap().value("id").toString(), "always"));
        QTRY_COMPARE(sent.last().value("id").toInt(), 5);
        QJsonObject decision = QJsonDocument::fromJson(text(sent.last()).toUtf8()).object();
        QCOMPARE(decision.value("behavior").toString(), QString("allow"));
        QCOMPARE(decision.value("updatedInput").toObject().value("command").toString(), QString("npm test"));
        QCOMPARE(ops.at(0).allowed, QStringList{"Bash(npm test:*)"});
        call(6, "tools/call", {{"name", "authorise"}, {"arguments", npm}});
        QTRY_COMPARE(sent.last().value("id").toInt(), 6);
        QVERIFY(ops.at(0).prompts.isEmpty());

        // And a denial.
        QJsonObject removal;
        removal.insert("tool_name", "Bash");
        removal.insert("input", QJsonObject{{"command", "rm -rf build"}});
        call(7, "tools/call", {{"name", "authorise"}, {"arguments", removal}});
        QTRY_COMPARE(ops.at(0).prompts.size(), 1);
        QVERIFY(ops.decide(0, ops.at(0).prompts.first().toMap().value("id").toString(), "deny"));
        QTRY_COMPARE(sent.last().value("id").toInt(), 7);
        decision = QJsonDocument::fromJson(text(sent.last()).toUtf8()).object();
        QCOMPARE(decision.value("behavior").toString(), QString("deny"));
    }

    void launchesWithTheFieldLink()
    {
        QTemporaryDir data, project, bin;
        const QString claude = fakeClaude(bin), log = bin.filePath("args.log");
        qputenv("FIRETEAM_TEST_LOG", log.toUtf8());
        Operations ops(data.path(), claude);
        QCOMPARE(ops.create("", project.path(), "Build", 1, "supervised", ""), 0);
        QSignalSpy finished(&ops, &Operations::operationFinished);
        ops.deploy(0);
        QVERIFY(finished.wait(10000));
        const QString run = QString::fromUtf8(read(log));
        QVERIFY(run.contains("--mcp-config\n{\"mcpServers\":{\"fireteam\""));
        QVERIFY(run.contains("--permission-prompt-tool\nmcp__fireteam__authorise"));
        QVERIFY(run.contains("mcp__fireteam__sitrep\nmcp__fireteam__request_orders"));
        QVERIFY(run.contains("--permission-mode\nacceptEdits"));
    }

    void parsesCampaignPlans()
    {
        auto plan = Stream::parseCampaignPlan("Plan.\n```json\n{\"summary\": \"S\", \"operations\": ["
                                              "{\"key\": \"Data Model\", \"objective\": \"A\", \"cycles\": 9},"
                                              "{\"key\": \"api\", \"objective\": \"B\", \"depends\": [\"data model\", \"nope\"], \"model\": \"GPT\"}]}\n```");
        QVERIFY(!plan.contains("error"));
        const QVariantList ops = plan.value("operations").toList();
        QCOMPARE(ops.size(), 2);
        QCOMPARE(ops.at(0).toMap().value("key").toString(), QString("data-model"));
        QCOMPARE(ops.at(0).toMap().value("cycles").toInt(), 8);
        QCOMPARE(ops.at(1).toMap().value("depends").toStringList(), QStringList{"data-model"});
        QCOMPARE(ops.at(1).toMap().value("model").toString(), QString());
        QCOMPARE(Stream::dependencyOrder(ops), (QStringList{"data-model", "api"}));
        auto loop = Stream::parseCampaignPlan("```json\n{\"operations\": [{\"key\": \"a\", \"objective\": \"x\", \"depends\": [\"b\"]},"
                                              "{\"key\": \"b\", \"objective\": \"y\", \"depends\": [\"a\"]}]}\n```");
        QVERIFY(loop.value("error").toString().contains("circle"));
        QVERIFY(Stream::parseCampaignPlan("No plan.").contains("error"));
    }

    void runsACampaignInDependencyOrder()
    {
        QTemporaryDir data, project, bin;
        const QString claude = fakeClaude(bin), log = bin.filePath("args.log");
        qputenv("FIRETEAM_TEST_LOG", log.toUtf8());
        qputenv("FIRETEAM_TEST_PER_OP", "1");
        // Cleared however the test ends, so later tests write notes.txt.
        struct Unset { ~Unset() { qunsetenv("FIRETEAM_TEST_PER_OP"); } } unset;
        QVERIFY(gitIn(project.path(), {"init", "-q", "-b", "main"}));
        write(project.filePath("app.txt"), "app\n");
        QVERIFY(gitIn(project.path(), {"add", "-A"}));
        QVERIFY(gitIn(project.path(), {"-c", "user.name=T", "-c", "user.email=t@x", "commit", "-q", "-m", "start"}));

        Operations ops(data.path(), claude);
        QSignalSpy changes(&ops, &Operations::campaignsChanged);
        const QString id = ops.planCampaign("habit tracker", project.path(), "Build a habit tracker", "");
        QVERIFY(!id.isEmpty());
        QTRY_COMPARE_WITH_TIMEOUT(ops.campaigns().first().toMap().value("status").toString(), QString("draft"), 10000);
        QVariantMap campaign = ops.campaigns().first().toMap();
        QCOMPARE(campaign.value("operations").toList().size(), 3);
        // The planner ran read-only.
        QVERIFY(QString::fromUtf8(read(log)).contains("--permission-mode\nplan"));

        // An edit that loops is refused; a sensible one sticks.
        QVariantList plan = campaign.value("operations").toList();
        QVariantMap schema = plan.at(0).toMap();
        schema.insert("depends", QStringList{"api"});
        QVERIFY(!ops.updateCampaignPlan(id, {schema, plan.at(1), plan.at(2)}));
        QVariantMap ui = plan.at(2).toMap();
        ui.insert("objective", "Build the UI, with tests.");
        QVERIFY(ops.updateCampaignPlan(id, {plan.at(0), plan.at(1), ui}));

        QVERIFY(ops.approveCampaign(id, "restricted", "off"));
        QCOMPARE(ops.rowCount(), 3);
        // Only the schema goes first.
        QCOMPARE(ops.deployedCount(), 1);
        QTRY_VERIFY2_WITH_TIMEOUT(ops.campaigns().first().toMap().value("status").toString() == "complete",
                                  qPrintable(ops.campaigns().first().toMap().value("error").toString()), 30000);

        // Everyone's work is merged in, and the dependents were told what
        // came before.
        for (const QString &name : {"stone-gate", "swift-river", "pale-moon"})
            QVERIFY2(QFile::exists(project.filePath("notes-" + name + ".txt")), qPrintable(name));
        const QStringList runs = QString::fromUtf8(read(log)).split("---\n", Qt::SkipEmptyParts);
        const QString api = runs.filter("OPERATION SWIFT RIVER").first();
        QVERIFY(api.contains("PRIOR WORK") && api.contains("STONE GATE"));
        QVERIFY(runs.filter("OPERATION PALE MOON").first().contains("Build the UI, with tests."));
        QCOMPARE(gitOut(project.path(), {"status", "--porcelain"}), QString());
        QVERIFY(QFile::exists(data.filePath("campaigns/" + id + "/dossier.html")));
    }

    void keepsLoadouts()
    {
        QTemporaryDir data;
        {
            Operations ops(data.path(), "/bin/true");
            QCOMPARE(ops.loadouts().size(), 3);
            ops.saveLoadout({{"name", "Night shift"}, {"model", "sonnet"}, {"cycles", 6}});
            ops.saveLoadout({{"name", "night shift"}, {"model", "opus"}, {"cycles", 2}});
            ops.removeLoadout("Recon");
            QCOMPARE(ops.loadouts().size(), 3);
        }
        Operations reloaded(data.path(), "/bin/true");
        QCOMPARE(reloaded.loadouts().last().toMap().value("model").toString(), QString("opus"));
        QCOMPARE(reloaded.loadouts().first().toMap().value("name").toString(), QString("Standard"));
    }

    void parsesOverwatchVerdicts()
    {
        auto review = Stream::parseReview("Fine.\n```json\n{\"grade\": \"Needs work\", \"summary\": \"Close.\", \"findings\": [{\"severity\": \"HIGH\", \"file\": \"a.c\", \"issue\": \"Leaks.\"}, {\"issue\": \"\"}]}\n```");
        QCOMPARE(review.value("grade").toString(), QString("needs-work"));
        QCOMPARE(review.value("findings").toList().size(), 1);
        QCOMPARE(review.value("findings").toList().first().toMap().value("severity").toString(), QString("high"));
        QVERIFY(Stream::reviewOrders(review).contains("[high] a.c: Leaks."));
        QCOMPARE(Stream::parseReview("No verdict here.").value("grade").toString(), QString("unknown"));
        QVERIFY(Stream::reviewReport("<X>", "o", 1, review, "Fine.").contains("&lt;X&gt;"));
    }

    void overwatchSendsBackForOneFix()
    {
        QTemporaryDir data, project, bin;
        const QString claude = fakeClaude(bin), log = bin.filePath("args.log");
        qputenv("FIRETEAM_TEST_LOG", log.toUtf8());
        QVERIFY(gitIn(project.path(), {"init", "-q"}));
        Operations ops(data.path(), claude);
        QCOMPARE(ops.create("", project.path(), "Write notes", 1, "restricted", "", 250000, false, "", "fix"), 0);
        QSignalSpy finished(&ops, &Operations::operationFinished);
        ops.deploy(0);
        QVERIFY(finished.wait(15000));

        // Cycle, review (needs work), fix cycle with the findings, review (pass).
        const Operation &op = ops.at(0);
        QCOMPARE(op.status, QString("complete"));
        QCOMPARE(op.cyclesDone, 2);
        QCOMPARE(op.reviews.size(), 2);
        QCOMPARE(op.reviews.first().toMap().value("grade").toString(), QString("needs-work"));
        QCOMPARE(op.reviews.last().toMap().value("grade").toString(), QString("pass"));
        QVERIFY(QFile::exists(op.reviews.first().toMap().value("file").toString()));
        QVERIFY(read(ops.dossierPath(op)).contains("Overwatch after cycle 2"));
        const QStringList runs = QString::fromUtf8(read(log)).split("---\n", Qt::SkipEmptyParts);
        QCOMPARE(runs.size(), 4);
        // The reviewer reads only, in a session of its own, with the diff.
        QVERIFY(runs.at(1).contains("--permission-mode\nplan") && !runs.at(1).contains("--resume"));
        QVERIFY(read(log + ".diff").contains("notes.txt"));
        // The fix cycle carries the findings and resumes the work session.
        QVERIFY(runs.at(2).contains("Add a title line.") && runs.at(2).contains("--resume\nsess-1"));
        QCOMPARE(op.sessionId, QString("sess-1"));
    }

    void readsContextUsage()
    {
        auto events = Stream::parseLine(R"({"type":"assistant","message":{"usage":{"input_tokens":2,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":5},"content":[]}})");
        QCOMPARE(events.size(), 1);
        QCOMPARE(events.first().kind, StreamEvent::Usage);
        QCOMPARE(events.first().contextTokens, 1107);
        events = Stream::parseLine(R"({"type":"result","subtype":"success","result":"ok","modelUsage":{"a":{"contextWindow":200000},"b":{"contextWindow":1000000}}})");
        QCOMPARE(events.first().contextWindow, 1000000);
        QCOMPARE(Stream::tokens(251400), QString("251k"));
        QCOMPARE(Stream::tokens(1000000), QString("1M"));
    }

    void reloadMarksLostAgentsInterrupted()
    {
        QTemporaryDir data;
        Operation op;
        op.id = "abc12345";
        op.codename = "COLD TIDE";
        op.status = "deployed";
        QFile file(data.filePath("operations.json"));
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(QJsonDocument(QJsonArray{op.toJson()}).toJson());
        file.close();

        Operations ops(data.path(), "/bin/true");
        QCOMPARE(ops.rowCount(), 1);
        QCOMPARE(ops.at(0).status, QString("interrupted"));
    }

    void reportsMissingClaude()
    {
        QTemporaryDir data, project;
        Operations ops(data.path(), data.filePath("missing-claude"));
        QCOMPARE(ops.create("", project.path(), "x", 1, "free", ""), 0);
        QSignalSpy finished(&ops, &Operations::operationFinished);
        ops.deploy(0);
        QVERIFY(finished.wait(5000));
        QCOMPARE(ops.at(0).status, QString("failed"));
    }

    void themeFallsBack()
    {
        QTemporaryDir dir;
        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QString("#FFD60A"));
        QCOMPARE(theme.accentForeground(), QString("black"));
    }

    void themeReadsAccent()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("theme");
        QFile colors(dir.path() + "/theme/colors.toml");
        QVERIFY(colors.open(QIODevice::WriteOnly));
        colors.write("accent = \"#112233\"\n");
        colors.close();

        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QString("#112233"));
        QCOMPARE(theme.accentForeground(), QString("white"));
    }

    void themeFollowsHyprlandRounding()
    {
        QTemporaryDir dir;
        const QString response = dir.filePath("response.json"), command = dir.filePath("hyprctl");
        auto write = [](const QString &path, const QByteArray &data) {
            QFile file(path);
            return file.open(QIODevice::WriteOnly) && file.write(data) == data.size();
        };
        QVERIFY(write(command, "#!/bin/sh\ncat '" + response.toUtf8() + "'\n"));
        QVERIFY(QFile::setPermissions(command, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
        QVERIFY(write(response, "{\"int\":0}"));

        Theme theme(dir.path(), nullptr, command);
        QCOMPARE(theme.radius(), 0);
        QVERIFY(write(response, "{\"int\":6}"));
        QTRY_COMPARE(theme.radius(), 6);
    }

    void translatorFallsBackToEnglish()
    {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("en"));
        QVERIFY(translator.translate("Main", "Save").isNull());
    }

    void translatorFollowsTheLanguageFile()
    {
        QTemporaryDir dir;
        write(dir.path() + "/language", "pt-BR\n");
        write(dir.path() + "/pt.json", R"({"Save": "Guardar", "Open": "Abrir"})");
        write(dir.path() + "/pt-BR.json", R"({"Save": "Salvar"})");

        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("pt-BR"));
        QCOMPARE(translator.translate("Main", "Save"), QString("Salvar"));
        QCOMPARE(translator.translate("Main", "Open"), QString("Abrir"));
        QVERIFY(translator.translate("Main", "Quit").isNull());
    }

    void translatorPicksPluralForms()
    {
        QTemporaryDir dir;
        write(dir.path() + "/language", "ru\n");
        write(dir.path() + "/en.json", R"({"%n clips": {"one": "%n clip", "other": "%n clips"}})");
        write(dir.path() + "/ru.json", R"({"%n clips": {"one": "%n клип", "few": "%n клипа", "many": "%n клипов", "other": "%n клипа"}})");

        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.translate("Main", "%n clips", nullptr, 21), QString("%n клип"));
        QCOMPARE(translator.translate("Main", "%n clips", nullptr, 22), QString("%n клипа"));
        QCOMPARE(translator.translate("Main", "%n clips", nullptr, 25), QString("%n клипов"));
        QCOMPARE(Translator::pluralCategory("ar", 11), QString("many"));
        QCOMPARE(Translator::pluralCategory("ja", 1), QString("other"));
    }
private:
    static QString fakeClaude(const QTemporaryDir &bin)
    {
        const QString claude = bin.filePath("claude");
        write(claude, fakeClaudeScript());
        QFile::setPermissions(claude, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        return claude;
    }
    static bool gitIn(const QString &directory, const QStringList &arguments)
    {
        QProcess git;
        git.setWorkingDirectory(directory);
        git.start("git", arguments);
        return git.waitForFinished(10000) && git.exitCode() == 0;
    }
    static QString gitOut(const QString &directory, const QStringList &arguments)
    {
        QProcess git;
        git.setWorkingDirectory(directory);
        git.start("git", arguments);
        git.waitForFinished(10000);
        return QString::fromUtf8(git.readAllStandardOutput());
    }
    static void write(const QString &path, const QByteArray &contents)
    {
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(contents);
    }
    static QByteArray read(const QString &path)
    {
        QFile file(path);
        return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
    }
};

QTEST_MAIN(FireteamTests)
#include "fireteam_tests.moc"
