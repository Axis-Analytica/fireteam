#include "stream.h"

#include <QDateTime>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QUrl>

namespace Stream {

// Commands whose first word is a tool and second its subcommand, so approving
// "npm test" doesn't approve "npm publish".
static const QStringList Runners{"npm", "pnpm", "yarn", "bun", "npx", "bunx", "cargo", "go", "git", "make", "just",
                                 "python", "python3", "uv", "pip", "pip3", "poetry", "docker", "podman", "deno",
                                 "dotnet", "mix", "bundle", "rails", "rake", "gradle", "mvn", "composer", "php",
                                 "swift", "zig", "kubectl", "gh", "pytest", "node", "ruby", "bin/rails"};

// Commands that only read, which Claude Code lets through on its own, so a
// chained command's approval doesn't need them.
static const QStringList ReadOnly{"echo", "printf", "cat", "head", "tail", "ls", "pwd", "wc", "grep", "rg", "find",
                                  "sort", "uniq", "which", "type", "true", "false", "test", "[", "date", "whoami",
                                  "basename", "dirname", "realpath", "readlink", "stat", "file", "diff", "cut", "tr",
                                  "cd", "tree", "du", "df", "less", "more", "column", "jq"};
static const QStringList GitReadOnly{"status", "log", "diff", "show", "rev-parse", "ls-files", "describe", "blame",
                                     "branch", "remote", "config", "shortlog", "reflog"};

// The rule prefix for one simple command: the program, plus its subcommand
// for runners like npm or git ("git -C . rev-parse"), so approving
// "npm test" doesn't approve "npm publish". Empty for a read-only command.
static QString prefixFor(const QString &command, bool *readOnly = nullptr) {
    QStringList words = command.simplified().split(' ', Qt::SkipEmptyParts);
    // Leading VAR=value assignments aren't the command.
    while (!words.isEmpty() && words.first().contains('=') && !words.first().startsWith('-'))
        words.removeFirst();
    if (readOnly)
        *readOnly = false;
    if (words.isEmpty())
        return {};
    int keep = 1;
    if (Runners.contains(words.first()) && words.size() > 1) {
        int i = 1;
        while (i < words.size() && words.at(i).startsWith('-'))
            i += QStringList{"-C", "-c", "--prefix", "--cwd", "-m"}.contains(words.at(i)) ? 2 : 1;
        keep = qMin(i + 1, int(words.size()));
        // "npm run build", not every script.
        if (i + 1 < words.size() && QStringList{"run", "exec", "run-script", "x", "dlx"}.contains(words.at(i)))
            keep = i + 2;
        if (readOnly && words.first() == "git" && i < words.size() && GitReadOnly.contains(words.at(i)))
            *readOnly = true;
    } else if (readOnly && ReadOnly.contains(words.first())) {
        *readOnly = true;
    }
    return words.mid(0, keep).join(' ');
}

QList<QStringList> rulesFor(const QString &tool, const QVariantMap &input) {
    if (tool == "Bash") {
        const QString command = input.value("command").toString().simplified();
        if (command.isEmpty())
            return {{tool}};
        // Claude Code checks each part of a chained command on its own, so a
        // chain is approved part by part, leaving out the parts that only read.
        static const QRegularExpression separators(R"(\s*(?:&&|\|\||;|\|)\s*)");
        const QStringList parts = command.split(separators, Qt::SkipEmptyParts);
        if (parts.size() > 1) {
            QStringList rules;
            for (const QString &part : parts) {
                bool readOnly = false;
                const QString prefix = prefixFor(part, &readOnly);
                const QString rule = QString("Bash(%1:*)").arg(prefix);
                if (!prefix.isEmpty() && !readOnly && !rules.contains(rule))
                    rules << rule;
            }
            return {rules.isEmpty() ? QStringList{QString("Bash(%1)").arg(command)} : rules};
        }
        const QString prefix = prefixFor(command);
        const QString broad = QString("Bash(%1:*)").arg(prefix);
        if (prefix == command)
            return {{broad}};
        return {{broad}, {QString("Bash(%1)").arg(command)}};
    }
    if (tool == "WebFetch") {
        const QString host = QUrl(input.value("url").toString()).host();
        if (!host.isEmpty())
            return {{QString("WebFetch(domain:%1)").arg(host)}};
    }
    return {{tool}};
}

QString ruleFromText(const QString &text) {
    const QString rule = text.simplified();
    static const QRegularExpression full(R"(^[A-Za-z_][\w-]*(\(.*\))?$)");
    if (rule.isEmpty())
        return {};
    // "Bash(make)" or "WebFetch" are rules already; anything else is a command.
    if (rule.contains('(') && full.match(rule).hasMatch())
        return rule;
    if (QStringList{"Bash", "Edit", "Write", "WebFetch", "WebSearch", "NotebookEdit"}.contains(rule))
        return rule;
    return rule.endsWith(":*") ? QString("Bash(%1)").arg(rule) : QString("Bash(%1:*)").arg(rule);
}

QString describeRule(const QString &rule) {
    static const QRegularExpression bash(R"(^Bash\((.*?)(:\*)?\)$)");
    const auto match = bash.match(rule);
    if (match.hasMatch())
        return match.captured(1) + (match.captured(2).isEmpty() ? QString() : QString(" …"));
    return rule;
}

QString describeTool(const QString &name, const QJsonObject &input) {
    // The most telling argument for each tool, so the comms feed reads like
    // "Edit src/main.cpp" rather than a JSON blob.
    for (const char *key : {"file_path", "command", "pattern", "url", "query", "description", "prompt"}) {
        const QString value = input.value(key).toString().simplified();
        if (!value.isEmpty()) {
            const bool path = QLatin1String(key) == QLatin1String("file_path");
            return name + "  " + (path ? QFileInfo(value).fileName() : value.left(140));
        }
    }
    return name;
}

QList<StreamEvent> parseLine(const QByteArray &line) {
    QList<StreamEvent> events;
    const QJsonDocument document = QJsonDocument::fromJson(line.trimmed());
    if (!document.isObject()) {
        const QString text = QString::fromUtf8(line).trimmed();
        if (!text.isEmpty())
            events.append({StreamEvent::Error, text});
        return events;
    }
    const QJsonObject object = document.object();
    const QString type = object.value("type").toString();

    if (type == "system" && object.value("subtype").toString() == "init") {
        StreamEvent event{StreamEvent::Session};
        event.sessionId = object.value("session_id").toString();
        event.text = object.value("model").toString();
        events.append(event);
    } else if (type == "assistant") {
        // Each turn reports its usage; everything sent in plus what came out
        // is what the session's context now holds.
        const QJsonObject usage = object.value("message").toObject().value("usage").toObject();
        if (!usage.isEmpty()) {
            StreamEvent event{StreamEvent::Usage};
            for (const char *key : {"input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens",
                                    "output_tokens"})
                event.contextTokens += usage.value(key).toInteger();
            events.append(event);
        }
        for (const auto &value : object.value("message").toObject().value("content").toArray()) {
            const QJsonObject block = value.toObject();
            const QString kind = block.value("type").toString();
            if (kind == "text") {
                const QString text = block.value("text").toString().trimmed();
                if (!text.isEmpty())
                    events.append({StreamEvent::Say, text});
            } else if (kind == "tool_use") {
                StreamEvent event{StreamEvent::Tool, describeTool(block.value("name").toString(),
                                                                  block.value("input").toObject())};
                event.toolId = block.value("id").toString();
                event.tool = block.value("name").toString();
                event.input = block.value("input").toObject().toVariantMap();
                events.append(event);
            }
        }
    } else if (type == "user") {
        // A tool result that's a refusal for want of approval, as it happens.
        for (const auto &value : object.value("message").toObject().value("content").toArray()) {
            const QJsonObject block = value.toObject();
            if (block.value("type").toString() != "tool_result" || !block.value("is_error").toBool())
                continue;
            QString text = block.value("content").toString();
            if (text.isEmpty())
                for (const auto &part : block.value("content").toArray())
                    text += part.toObject().value("text").toString();
            static const QRegularExpression refusal(R"(requires approval|haven't granted|permission to use|was blocked)",
                                                    QRegularExpression::CaseInsensitiveOption);
            if (text.contains(refusal)) {
                StreamEvent event{StreamEvent::Denied, text.trimmed().left(300)};
                event.toolId = block.value("tool_use_id").toString();
                events.append(event);
            }
        }
    } else if (type == "rate_limit_event") {
        const QJsonObject info = object.value("rate_limit_info").toObject();
        StreamEvent event{StreamEvent::RateLimit};
        event.limitStatus = info.value("status").toString();
        event.resetsAt = info.value("resetsAt").toInteger();
        event.text = info.value("rateLimitType").toString();
        event.windows = info.value("unifiedWindows").toObject().toVariantMap();
        events.append(event);
    } else if (type == "result") {
        StreamEvent event{StreamEvent::Result};
        event.text = object.value("result").toString().trimmed();
        event.sessionId = object.value("session_id").toString();
        event.costUsd = object.value("total_cost_usd").toDouble();
        event.turns = object.value("num_turns").toInt();
        const QJsonObject models = object.value("modelUsage").toObject();
        for (auto it = models.begin(); it != models.end(); ++it)
            event.contextWindow = qMax(event.contextWindow, it.value().toObject().value("contextWindow").toInteger());
        event.isError = object.value("is_error").toBool() || object.value("subtype").toString() != "success";
        if (event.text.isEmpty() && event.isError)
            event.text = object.value("subtype").toString();
        for (const auto &value : object.value("permission_denials").toArray()) {
            const QJsonObject denial = value.toObject();
            event.denials.append(QVariantMap{{"tool", denial.value("tool_name").toString()},
                                             {"input", denial.value("tool_input").toObject().toVariantMap()}});
        }
        events.append(event);
    }
    return events;
}

bool isUsageLimit(const QString &text) {
    static const QRegularExpression limit(R"(usage limit|limit reached|hit your limit|rate limit|resets? (at )?\d)",
                                          QRegularExpression::CaseInsensitiveOption);
    return text.contains(limit);
}

QString systemBrief() {
    return "You are one agent on a fireteam, working unattended through a series of development cycles. "
           "No one will answer questions mid-cycle, so make sensible decisions, note them, and keep moving. "
           "Each cycle should leave the project working and a little closer to the objective. "
           "Run shell commands one at a time rather than chained with ; && or |, so each can be approved on its "
           "own. If a command is refused for want of approval, don't retry it or look for a way around it: carry on "
           "without it and list it in the debrief. Fireteam passes refusals to the operator, and approved "
           "commands work from the next cycle.";
}

QString cyclePrompt(const QString &codename, const QString &objective, int cycle, int cycles,
                    const QString &reportPath, const QString &handoffBrief, const QString &debriefs,
                    const QStringList &commandOrders, const QString &standing) {
    QString orders;
    if (cycle == 1)
        orders = "This is the first cycle. Survey the project, plan the route to the objective, then deliver "
                 "the first meaningful increment.";
    else
        orders = "Continue from the previous cycle. Pick the next most valuable increment toward the objective "
                 "and deliver it.";
    if (cycle == cycles)
        orders += " This is the final cycle: finish, verify, and leave the project in a clean, working state.";
    if (!handoffBrief.isEmpty())
        orders += QString("\n\nHANDOFF:\nYou are a fresh session taking over this operation from one whose context "
                          "grew too large. Before anything else, read the handoff brief at %1. Earlier debriefs are "
                          "in %2 if you need more detail.").arg(handoffBrief, debriefs);
    if (!standing.trimmed().isEmpty())
        orders += "\n\nSTANDING ORDERS:\nThese hold for every cycle of this operation.\n" + standing.trimmed();
    if (!commandOrders.isEmpty())
        orders += "\n\nORDERS FROM COMMAND:\nThe operator sent these since the last cycle. They take priority over "
                  "the plan above; follow them this cycle and say in the debrief how each was handled.\n- "
                  + commandOrders.join("\n- ");

    return QString("OPERATION %1, CYCLE %2 OF %3\n\nOBJECTIVE:\n%4\n\nORDERS:\n%5\n\n"
                   "When this cycle's work is done, write a debrief as one self-contained HTML file to:\n%6\n"
                   "Cover what was done this cycle, the files changed, how it was verified, problems found, and "
                   "the plan for the next cycle. Use inline CSS only with a dark background, and no external "
                   "resources. End with a two-sentence plain-text summary as your final reply.")
        .arg(codename).arg(cycle).arg(cycles).arg(objective, orders, reportPath);
}

QString handoffPrompt(const QString &codename, const QString &objective, qint64 contextTokens, int cyclesLeft,
                      const QString &briefPath, int midCycle) {
    const QString cutShort = midCycle > 0
        ? QString("You were stopped part-way through cycle %1, so the fresh session will finish that cycle. Record "
                  "exactly what was in progress: what is half-done, which files are mid-edit, and what is left of "
                  "this cycle's work.\n\n").arg(midCycle)
        : QString();
    return QString("OPERATION %1, HANDOFF\n\nOBJECTIVE:\n%2\n\n"
                   "This session's context has reached %3 tokens, so a fresh session will take over for the "
                   "remaining %4 cycle(s). It will start with no memory of this one.\n\n" + cutShort +
                   "Write a handoff brief as Markdown to:\n%5\n"
                   "Cover how far along the objective is; what has been built, with the key files and how they fit "
                   "together; decisions made and why; how to build, run, and test; known problems; and the exact "
                   "next steps. Be complete but concise: the next session reads only this brief and the debriefs. "
                   "Don't change the project in this step. Reply with one sentence when done.")
        .arg(codename, objective, tokens(contextTokens)).arg(cyclesLeft).arg(briefPath);
}

QString tokens(qint64 count) {
    if (count >= 1000000)
        return QString::number(count / 1000000.0, 'f', count % 1000000 ? 1 : 0) + "M";
    if (count >= 1000)
        return QString::number(qRound64(count / 1000.0)) + "k";
    return QString::number(count);
}

static QString page(const QString &title, const QString &body) {
    return QString(R"(<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>%1</title>
<style>
body{margin:0;background:#07090b;color:#e8e6e1;font:15px/1.6 system-ui,sans-serif}
main{max-width:860px;margin:0 auto;padding:40px 20px}
h1{font-size:34px;letter-spacing:.12em;text-transform:uppercase;margin:0}
h2{font-size:13px;letter-spacing:.3em;text-transform:uppercase;color:#f97316;margin:32px 0 8px}
.tag{font:12px ui-monospace,monospace;letter-spacing:.2em;color:#8b8f94;text-transform:uppercase}
.panel{background:#0f1215;border:1px solid #1f2428;border-left:3px solid #f97316;padding:14px 18px;white-space:pre-wrap}
ul{font:13px/1.7 ui-monospace,monospace;color:#c4c2bd;padding-left:18px}
a{color:#f97316}
</style></head><body><main>%2</main></body></html>
)").arg(title.toHtmlEscaped(), body);
}

static QString list(const QStringList &items, const QString &empty) {
    if (items.isEmpty())
        return "<p class=\"tag\">" + empty + "</p>";
    QString html = "<ul>";
    for (const auto &item : items)
        html += "<li>" + item.toHtmlEscaped() + "</li>";
    return html + "</ul>";
}

QString fallbackReport(const QString &codename, int cycle, int cycles, const QString &objective,
                       const QString &sitrep, const QStringList &actions, const QStringList &intel) {
    const QString body =
        QString("<div class=\"tag\">Debrief · cycle %1 of %2 · %3</div><h1>%4</h1>"
                "<h2>Objective</h2><div class=\"panel\">%5</div>"
                "<h2>Sitrep</h2><div class=\"panel\">%6</div>"
                "<h2>Field actions</h2>%7<h2>Changed files</h2>%8"
                "<p class=\"tag\">The agent left no debrief of its own; Fireteam wrote this one from the comms.</p>")
            .arg(cycle).arg(cycles)
            .arg(QDateTime::currentDateTime().toString(Qt::ISODate), codename.toHtmlEscaped(),
                 objective.toHtmlEscaped(), sitrep.isEmpty() ? "No sitrep." : sitrep.toHtmlEscaped(),
                 list(actions, "None recorded."), list(intel, "No git changes detected."));
    return page(codename + " · cycle " + QString::number(cycle), body);
}

static QString gradeLabel(const QString &grade) {
    return grade == "pass" ? "Pass" : grade == "needs-work" ? "Needs work" : grade == "fail" ? "Fail" : "No verdict";
}
static QString gradeColour(const QString &grade) {
    return grade == "pass" ? "#86e07d" : grade == "needs-work" ? "#e9b44c" : grade == "fail" ? "#ff4f45" : "#8b8f94";
}

QString dossier(const QString &codename, const QString &objective, const QString &directory,
                const QList<DossierEntry> &entries, const QVariantList &reviews) {
    QString cycles;
    for (const QVariant &value : reviews) {
        const QVariantMap review = value.toMap();
        cycles += QString("<h2 style=\"color:%1\">Overwatch after cycle %2 · %3 · <a href=\"%4\">open review</a></h2>"
                          "<div class=\"panel\" style=\"border-left-color:%1\">%5</div>")
                      .arg(gradeColour(review.value("grade").toString()))
                      .arg(review.value("cycle").toInt())
                      .arg(gradeLabel(review.value("grade").toString()),
                           ("reviews/" + QFileInfo(review.value("file").toString()).fileName()).toHtmlEscaped(),
                           review.value("summary").toString().toHtmlEscaped());
    }
    for (const auto &entry : entries)
        cycles += QString("<h2>Cycle %1 · <a href=\"%2\">open debrief</a></h2><div class=\"panel\">%3</div>")
                      .arg(entry.cycle).arg(entry.file.toHtmlEscaped(),
                                            entry.sitrep.isEmpty() ? "No sitrep." : entry.sitrep.toHtmlEscaped());
    const QString body = QString("<div class=\"tag\">Operation dossier · %1</div><h1>%2</h1>"
                                 "<h2>Objective</h2><div class=\"panel\">%3</div>%4")
                             .arg(directory.toHtmlEscaped(), codename.toHtmlEscaped(), objective.toHtmlEscaped(),
                                  cycles.isEmpty() ? "<p class=\"tag\">No cycles completed yet.</p>" : cycles);
    return page(codename + " · dossier", body);
}

QString codename(quint32 seed) {
    static const char *first[] = {"IRON", "SILENT", "BLACK", "COLD", "GHOST", "RED", "STEEL", "NIGHT",
                                  "GRAVE", "AMBER", "BROKEN", "HOLLOW", "WINTER", "COPPER", "ASH", "FERAL"};
    static const char *second[] = {"VIPER", "ANVIL", "TALON", "HARBOR", "LANTERN", "SPIRE", "WOLF", "CINDER",
                                   "RAVEN", "CITADEL", "MERIDIAN", "HAMMER", "TIDE", "SABLE", "KESTREL", "FORGE"};
    return QString("%1 %2").arg(first[seed % 16], second[(seed / 16) % 16]);
}

QString reviewPrompt(const QString &codename, const QString &objective, int cycles, const QString &diffPath,
                     const QString &debriefs) {
    const QString evidence = diffPath.isEmpty()
        ? QString("The project isn't a git repository, so there's no diff: inspect the project files directly.")
        : QString("Everything the operation changed is in this diff (read it first, then open the files it touches "
                  "for context):\n%1").arg(diffPath);
    return QString("OPERATION %1, OVERWATCH REVIEW\n\nOBJECTIVE:\n%2\n\n"
                   "You are overwatch: an independent reviewer who wasn't part of this operation. The fireteam has "
                   "finished %3 cycle(s). Judge whether the work meets the objective and is sound.\n\n%4\n\n"
                   "The fireteam's own debriefs are in %5 if you want its account, but judge the code, not the "
                   "claims. You may read files and run read-only commands (tests included, if they're allowed); "
                   "don't change anything.\n\n"
                   "Look for: parts of the objective not done, bugs, broken or missing tests, security problems, and "
                   "anything left half-finished. Ignore style nits.\n\n"
                   "Write your review in plain prose, then end your reply with exactly one fenced json block:\n"
                   "```json\n{\"grade\": \"pass\" | \"needs-work\" | \"fail\", \"summary\": \"two sentences\", "
                   "\"findings\": [{\"severity\": \"high\" | \"medium\" | \"low\", \"file\": \"path or empty\", "
                   "\"issue\": \"what's wrong and what to do\"}]}\n```\n"
                   "Grade pass only if the objective is met with no high-severity findings.")
        .arg(codename, objective).arg(cycles).arg(evidence, debriefs);
}

QVariantMap parseReview(const QString &reply) {
    static const QRegularExpression block(R"(```json\s*(\{.*?\})\s*```)", QRegularExpression::DotMatchesEverythingOption);
    QJsonObject verdict;
    auto blocks = block.globalMatch(reply);
    while (blocks.hasNext()) {
        const QJsonDocument document = QJsonDocument::fromJson(blocks.next().captured(1).toUtf8());
        if (document.isObject())
            verdict = document.object();
    }
    QString grade = verdict.value("grade").toString().toLower().replace(' ', '-').replace('_', '-');
    if (!QStringList{"pass", "needs-work", "fail"}.contains(grade))
        grade = "unknown";
    QVariantList findings;
    for (const auto &value : verdict.value("findings").toArray()) {
        const QJsonObject finding = value.toObject();
        if (!finding.value("issue").toString().trimmed().isEmpty())
            findings.append(QVariantMap{{"severity", finding.value("severity").toString("medium").toLower()},
                                        {"file", finding.value("file").toString()},
                                        {"issue", finding.value("issue").toString().trimmed()}});
    }
    QString summary = verdict.value("summary").toString().trimmed();
    if (summary.isEmpty())
        summary = reply.section("```", 0, 0).trimmed().left(400);
    return {{"grade", grade}, {"summary", summary}, {"findings", findings}};
}

QString reviewReport(const QString &codename, const QString &objective, int cycle, const QVariantMap &review,
                     const QString &reply) {
    const QString grade = review.value("grade").toString();
    QString findings;
    for (const QVariant &value : review.value("findings").toList()) {
        const QVariantMap finding = value.toMap();
        const QString severity = finding.value("severity").toString();
        findings += QString("<li><b style=\"color:%1\">%2</b> %3%4</li>")
                        .arg(severity == "high" ? "#ff4f45" : severity == "medium" ? "#e9b44c" : "#8b8f94",
                             severity.toUpper().toHtmlEscaped(),
                             finding.value("file").toString().isEmpty()
                                 ? QString() : "<code>" + finding.value("file").toString().toHtmlEscaped() + "</code> ",
                             finding.value("issue").toString().toHtmlEscaped());
    }
    const QString prose = reply.section("```json", 0, 0).trimmed();
    const QString body = QString("<div class=\"tag\">Overwatch review · after cycle %1</div><h1>%2</h1>"
                                 "<h2 style=\"color:%3\">%4</h2><div class=\"panel\" style=\"border-left-color:%3\">%5</div>"
                                 "<h2>Objective</h2><div class=\"panel\">%6</div>"
                                 "<h2>Findings</h2>%7<h2>Review</h2><div class=\"panel\">%8</div>")
                             .arg(cycle)
                             .arg(codename.toHtmlEscaped(), gradeColour(grade), gradeLabel(grade),
                                  review.value("summary").toString().toHtmlEscaped(), objective.toHtmlEscaped(),
                                  findings.isEmpty() ? "<p class=\"tag\">None.</p>" : "<ul>" + findings + "</ul>",
                                  prose.toHtmlEscaped());
    return page(codename + " · overwatch", body);
}

QString reviewOrders(const QVariantMap &review) {
    QStringList lines{QString("Overwatch reviewed the work and graded it %1: %2")
                          .arg(gradeLabel(review.value("grade").toString()).toLower(), review.value("summary").toString()),
                      "Fix these findings this cycle:"};
    for (const QVariant &value : review.value("findings").toList()) {
        const QVariantMap finding = value.toMap();
        lines << QString("- [%1] %2%3").arg(finding.value("severity").toString(),
                                            finding.value("file").toString().isEmpty() ? QString()
                                                : finding.value("file").toString() + ": ",
                                            finding.value("issue").toString());
    }
    return lines.join('\n');
}

}
