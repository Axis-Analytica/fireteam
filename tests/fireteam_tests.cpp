#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>

#include "operations.h"
#include "stream.h"
#include "theme.h"
#include "translator.h"

// A stand-in for claude: prints a stream-json session, records its arguments,
// and writes the debrief the prompt asks for on the first cycle only, so both
// the agent's own report and Fireteam's fallback are exercised. When the
// FIRETEAM_TEST_STALL file exists, one run reports a huge context and then
// hangs, the way a runaway cycle would.
static const char *FakeClaude = R"(#!/bin/sh
printf '%s\n' "$@" >> "$FIRETEAM_TEST_LOG"
echo '---' >> "$FIRETEAM_TEST_LOG"
if [ "$1" = auth ]; then echo '{"loggedIn":true,"email":"agent@example.com","subscriptionType":"max"}'; exit 0; fi
prompt="$2"
report=$(printf '%s\n' "$prompt" | grep '/debriefs/cycle-')
brief=$(printf '%s\n' "$prompt" | grep '^/.*/handoffs/session-..\.md$')
echo '{"type":"system","subtype":"init","session_id":"sess-1","model":"test-model"}'
if [ -n "$brief" ]; then echo '# brief' > "$brief"; echo '{"type":"result","subtype":"success","is_error":false,"result":"Brief written.","session_id":"sess-1","total_cost_usd":0.01}'; exit 0; fi
if [ -n "$FIRETEAM_TEST_STALL" ] && [ -f "$FIRETEAM_TEST_STALL" ]; then rm "$FIRETEAM_TEST_STALL"; echo '{"type":"assistant","message":{"usage":{"input_tokens":900000,"output_tokens":0},"content":[]}}'; exec sleep 20; fi
echo '{"type":"assistant","message":{"usage":{"input_tokens":'${FIRETEAM_TEST_CONTEXT:-1000}',"output_tokens":0},"content":[{"type":"text","text":"Moving out."},{"type":"tool_use","name":"Edit","input":{"file_path":"/x/src/main.cpp"}}]}}'
case "$report" in *cycle-01.html) echo '<html>agent debrief</html>' > "$report";; esac
echo '{"type":"result","subtype":"success","is_error":false,"result":"Cycle done.","session_id":"sess-1","total_cost_usd":0.25,"num_turns":3}'
)";

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
        write(claude, FakeClaude);
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
        write(claude, FakeClaude);
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
        write(claude, FakeClaude);
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
        write(claude, FakeClaude);
        QFile::setPermissions(claude, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        return claude;
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
