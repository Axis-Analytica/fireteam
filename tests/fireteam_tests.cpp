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
// the agent's own report and Fireteam's fallback are exercised.
static const char *FakeClaude = R"(#!/bin/sh
printf '%s\n' "$@" >> "$FIRETEAM_TEST_LOG"
echo '---' >> "$FIRETEAM_TEST_LOG"
if [ "$1" = auth ]; then echo '{"loggedIn":true,"email":"agent@example.com","subscriptionType":"max"}'; exit 0; fi
prompt="$2"
report=$(printf '%s\n' "$prompt" | grep '/debriefs/cycle-')
echo '{"type":"system","subtype":"init","session_id":"sess-1","model":"test-model"}'
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Moving out."},{"type":"tool_use","name":"Edit","input":{"file_path":"/x/src/main.cpp"}}]}}'
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
