#include "stream.h"

#include <QDateTime>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSet>
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
static const QStringList ReadOnly{"echo", "printf", "cat", "head", "sed", "awk", "nl", "less", "xxd", "tail", "ls", "pwd", "wc", "grep", "rg", "find",
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

// A command's own words, without the text it feeds in: heredoc bodies and
// quoted strings carry code and prose whose ; and | aren't separators.
static QString commandWords(const QString &command) {
    QString text = command;
    static const QRegularExpression heredoc(R"(<<-?\s*(['"]?)(\w+)\1[^\n]*\n.*?\n\s*\2\s*(\n|$))",
                                            QRegularExpression::DotMatchesEverythingOption);
    text.replace(heredoc, "<<HEREDOC\n");
    static const QRegularExpression quoted(R"('[^']*'|"(?:[^"\\]|\\.)*")");
    text.replace(quoted, "STRING");
    return text;
}

QList<QStringList> rulesFor(const QString &tool, const QVariantMap &input) {
    if (tool == "Bash") {
        const QString raw = input.value("command").toString();
        const QString command = raw.simplified();
        if (command.isEmpty())
            return {{tool}};
        // Claude Code checks each part of a chained command on its own, so a
        // chain is approved part by part, leaving out the parts that only read.
        // Only the command's own words are split: not what a heredoc or a
        // quoted string feeds it.
        static const QRegularExpression separators(R"(\s*(?:&&|\|\||;|\||\n)\s*)");
        const QStringList parts = commandWords(raw).split(separators, Qt::SkipEmptyParts);
        // A part that doesn't start like a program (a stray brace, a keyword
        // fragment) isn't one.
        static const QRegularExpression program(R"(^(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*[A-Za-z0-9_./~-]+(\s|$))");
        if (parts.size() > 1) {
            QStringList rules;
            for (const QString &part : parts) {
                if (!program.match(part.trimmed()).hasMatch())
                    continue;
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
    return "You are one agent on a fireteam, working through a series of development cycles mostly unattended. "
           "Make sensible decisions, note them, and keep moving. Report progress at real milestones with the "
           "fireteam sitrep tool. When a decision is genuinely the operator's (a direction, a trade-off, missing "
           "information), ask with the fireteam request_orders tool and wait for the answer; otherwise decide "
           "yourself. "
           "Each cycle should leave the project working and a little closer to the objective. "
           "Work in your current directory: it is the project, or a git worktree of it on a branch of its own. "
           "Don't change files elsewhere, even if a path in your orders points at another copy of the project. "
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
                   "the plan for the next cycle. Use inline CSS only and no external resources, styled like Fireteam: "
                   "a near-black ground (#0f100e) with raised panels (#161714), 1px hairlines (#2a2b27), pale ink "
                   "(#ecebe6) and muted text (#93948d), one accent (#ffd60a) used sparingly; headings, figures and code "
                   "in a monospace stack, prose in a sans stack; square corners, no shadows or gradients, sentence "
                   "case. End with a two-sentence plain-text summary as your final reply.")
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
body{margin:0;background:#0f100e;color:#ecebe6;font:15px/1.6 "Red Hat Text",system-ui,sans-serif}
main{max-width:860px;margin:0 auto;padding:48px 20px}
h1{font:500 34px/1.1 "Martian Mono",ui-monospace,monospace;letter-spacing:-.02em;margin:0}
h2{font:500 14px "Red Hat Text",system-ui,sans-serif;color:#c9c8c1;margin:36px 0 10px;padding-bottom:6px;border-bottom:1px solid #2a2b27}
h2::before{content:"";display:inline-block;width:5px;height:5px;background:#ffd60a;margin-right:10px;vertical-align:middle}
.tag{font:12px ui-monospace,monospace;color:#93948d}
.panel{background:#161714;border:1px solid #2a2b27;border-left:2px solid #ffd60a;padding:14px 18px;white-space:pre-wrap}
ul{font:13px/1.7 "Martian Mono",ui-monospace,monospace;color:#c9c8c1;padding-left:18px}
a{color:#ffd60a}
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

QString criteriaBlock(const QVariantList &criteria) {
    if (criteria.isEmpty())
        return {};
    QStringList lines{"ACCEPTANCE CRITERIA: the operation is done when all of these are met. When you've met and "
                      "verified one, mark it with the fireteam mark_objective tool (by number), with your evidence."};
    for (int i = 0; i < criteria.size(); ++i) {
        const QVariantMap criterion = criteria.at(i).toMap();
        const QString state = criterion.value("state").toString();
        lines << QString("%1. %2%3").arg(i + 1).arg(criterion.value("text").toString(),
                                                    state == "met" ? " (verified)" : state == "claimed" ? " (you marked this met)"
                                                    : state == "unmet" ? " (overwatch found this NOT met)" : "");
    }
    return lines.join('\n');
}

QString gateOrders(const QVariantList &results) {
    QStringList lines;
    for (const QVariant &value : results) {
        const QVariantMap gate = value.toMap();
        if (gate.value("passed").toBool())
            continue;
        lines << QString("- %1 (`%2`) failed. The end of its output:\n%3")
                     .arg(gate.value("name").toString(), gate.value("command").toString(),
                          gate.value("output").toString().right(1500));
    }
    if (lines.isEmpty())
        return {};
    return "GATES FAILED: Fireteam ran the project's checks after the last cycle, and these failed. Fix them first "
           "this cycle; the operation isn't done until they pass.\n" + lines.join('\n');
}

QString reviewPrompt(const QString &codename, const QString &objective, int cycles, const QString &diffPath,
                     const QString &debriefs, const QVariantList &criteria, const QVariantList &gates) {
    // Criteria to check one by one, and what Fireteam's own checks found.
    QString extra;
    if (!criteria.isEmpty()) {
        extra += "\n\nACCEPTANCE CRITERIA to check one by one (the agent's own claims don't count):";
        for (int i = 0; i < criteria.size(); ++i)
            extra += QString("\n%1. %2").arg(i + 1).arg(criteria.at(i).toMap().value("text").toString());
        extra += "\nAdd to your json a \"criteria\" list: [{\"index\": 1, \"met\": true, \"note\": \"how you know\"}], one per "
                 "criterion. Grade pass only if every criterion is met.";
    }
    if (!gates.isEmpty()) {
        extra += "\n\nFireteam ran the project's checks after the last cycle:";
        for (const QVariant &value : gates)
            extra += QString("\n- %1 (`%2`): %3").arg(value.toMap().value("name").toString(),
                                                     value.toMap().value("command").toString(),
                                                     value.toMap().value("passed").toBool() ? "passed" : "FAILED");
    }
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
        .arg(codename, objective).arg(cycles).arg(evidence, debriefs) + extra;
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
    QVariantList criteria;
    for (const auto &value : verdict.value("criteria").toArray()) {
        const QJsonObject criterion = value.toObject();
        if (criterion.value("index").toInt() > 0)
            criteria.append(QVariantMap{{"index", criterion.value("index").toInt()}, {"met", criterion.value("met").toBool()},
                                        {"note", criterion.value("note").toString()}});
    }
    return {{"grade", grade}, {"summary", summary}, {"findings", findings}, {"criteria", criteria}};
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

QString campaignPrompt(const QString &name, const QString &objective) {
    return QString("CAMPAIGN %1, PLANNING\n\nOBJECTIVE:\n%2\n\n"
                   "You are the planner for a campaign: a large objective carried out by several Claude Code agents, "
                   "each running its own operation through a few development cycles. Survey this project first "
                   "(read files, run read-only commands; change nothing), then break the objective into operations.\n\n"
                   "Rules for a good plan:\n"
                   "- 2 to 8 operations, each a coherent piece of work one agent can finish and verify in 1 to 5 cycles.\n"
                   "- Each objective is self-contained: an agent that sees only its own objective, and the summaries of "
                   "the operations it depends on, can do it.\n"
                   "- Dependencies only where one operation truly needs another's work; independent operations run in "
                   "parallel on separate git branches and are merged in as they finish, so avoid two operations "
                   "editing the same files at the same time.\n"
                   "- No dependency cycles. Prefer a shallow graph.\n"
                   "- Models: haiku for small mechanical work, sonnet for most, opus for the hardest design work.\n\n"
                   "Explain the plan briefly in prose, then end your reply with exactly one fenced json block:\n"
                   "```json\n{\"summary\": \"two sentences on the approach\", \"operations\": [{\"key\": \"short-id\", "
                   "\"codename\": \"TWO WORDS\", \"objective\": \"what this operation must deliver, and how to verify it\", "
                   "\"cycles\": 2, \"model\": \"sonnet\", \"depends\": [\"other-key\"], "
                   "\"criteria\": [\"a checkable statement of done\"]}]}\n```\n"
                   "Give each operation 2 to 4 acceptance criteria that someone could check by reading the code or "
                   "running it.")
        .arg(name, objective);
}

QStringList dependencyOrder(const QVariantList &operations) {
    QHash<QString, QStringList> depends;
    QStringList keys;
    for (const QVariant &value : operations) {
        const QVariantMap op = value.toMap();
        keys << op.value("key").toString();
        depends.insert(op.value("key").toString(), op.value("depends").toStringList());
    }
    QStringList order;
    QSet<QString> placed;
    // Repeatedly place whatever has all its dependencies placed.
    while (order.size() < keys.size()) {
        bool progress = false;
        for (const QString &key : keys) {
            if (placed.contains(key))
                continue;
            bool ready = true;
            for (const QString &dependency : depends.value(key))
                ready = ready && placed.contains(dependency);
            if (ready) {
                order << key;
                placed.insert(key);
                progress = true;
            }
        }
        if (!progress)
            return {};
    }
    return order;
}

QVariantMap parseCampaignPlan(const QString &reply) {
    static const QRegularExpression block(R"(```json\s*(\{.*\})\s*```)", QRegularExpression::DotMatchesEverythingOption);
    QJsonObject plan;
    auto blocks = block.globalMatch(reply);
    while (blocks.hasNext()) {
        const QJsonDocument document = QJsonDocument::fromJson(blocks.next().captured(1).toUtf8());
        if (document.isObject())
            plan = document.object();
    }
    const QJsonArray raw = plan.value("operations").toArray();
    if (raw.isEmpty())
        return {{"error", "The planner's reply had no plan in it."}};
    QVariantList operations;
    QSet<QString> keys;
    for (const auto &value : raw) {
        const QJsonObject op = value.toObject();
        QString key = op.value("key").toString().trimmed().toLower();
        key.replace(QRegularExpression("[^a-z0-9]+"), "-");
        if (key.isEmpty() || keys.contains(key))
            key = QString("op-%1").arg(operations.size() + 1);
        keys.insert(key);
        const QString objective = op.value("objective").toString().trimmed();
        if (objective.isEmpty())
            continue;
        QStringList depends;
        for (const auto &dependency : op.value("depends").toArray()) {
            QString name = dependency.toString().trimmed().toLower();
            name.replace(QRegularExpression("[^a-z0-9]+"), "-");
            depends << name;
        }
        const QString model = op.value("model").toString().toLower();
        operations.append(QVariantMap{{"key", key}, {"codename", op.value("codename").toString().trimmed().toUpper()},
                                      {"objective", objective}, {"cycles", qBound(1, op.value("cycles").toInt(2), 8)},
                                      {"model", QStringList{"opus", "sonnet", "haiku"}.contains(model) ? model : QString()},
                                      {"depends", depends}, {"criteria", [&] {
                                          QStringList criteria;
                                          for (const auto &item : op.value("criteria").toArray())
                                              if (!item.toString().trimmed().isEmpty())
                                                  criteria << item.toString().trimmed();
                                          return criteria.mid(0, 8);
                                      }()}});
    }
    // Dependencies on operations that don't exist are dropped, not fatal.
    for (QVariant &value : operations) {
        QVariantMap op = value.toMap();
        QStringList depends;
        for (const QString &dependency : op.value("depends").toStringList())
            if (keys.contains(dependency) && dependency != op.value("key").toString())
                depends << dependency;
        op.insert("depends", depends);
        value = op;
    }
    if (operations.isEmpty())
        return {{"error", "The planner's plan had no usable operations."}};
    if (operations.size() > 10)
        operations = operations.mid(0, 10);
    if (dependencyOrder(operations).isEmpty())
        return {{"error", "The planner's dependencies go round in a circle."}};
    return {{"summary", plan.value("summary").toString().trimmed()}, {"operations", operations}};
}

QString priorWork(const QList<QVariantMap> &done) {
    if (done.isEmpty())
        return {};
    QStringList lines{"PRIOR WORK: this operation is part of a campaign and builds on operations that have finished "
                      "and been merged into the project. What they did:"};
    for (const QVariantMap &op : done) {
        lines << QString("- %1: %2\n  Result: %3").arg(op.value("codename").toString(), op.value("objective").toString(),
                                                     op.value("sitrep").toString().isEmpty() ? "No sitrep." : op.value("sitrep").toString());
        if (!op.value("brief").toString().isEmpty())
            lines << "  Details: " + op.value("brief").toString();
    }
    lines << "Read those for context if you need it; don't redo their work.";
    return lines.join('\n');
}

QString campaignDossier(const QString &name, const QString &objective, const QString &summary,
                        const QVariantList &operations) {
    QString rows;
    for (const QVariant &value : operations) {
        const QVariantMap op = value.toMap();
        const QString status = op.value("status").toString();
        const QString colour = status == "complete" ? "#86e07d" : status == "failed" || status == "aborted" ? "#ff4f45"
                             : status == "deployed" ? "#f97316" : "#8b8f94";
        rows += QString("<h2 style=\"color:%1\">%2 · %3%4</h2><div class=\"panel\" style=\"border-left-color:%1\">%5\n\n%6</div>")
                    .arg(colour, op.value("codename").toString().toHtmlEscaped(), status.toUpper().toHtmlEscaped(),
                         op.value("dossier").toString().isEmpty()
                             ? QString() : QString(" · <a href=\"%1\">dossier</a>").arg(QUrl::fromLocalFile(op.value("dossier").toString()).toString().toHtmlEscaped()),
                         op.value("objective").toString().toHtmlEscaped(),
                         op.value("sitrep").toString().isEmpty() ? QString() : "Result: " + op.value("sitrep").toString().toHtmlEscaped());
    }
    const QString body = QString("<div class=\"tag\">Campaign dossier</div><h1>%1</h1><h2>Objective</h2><div class=\"panel\">%2</div>"
                                 "<h2>Plan</h2><div class=\"panel\">%3</div>%4")
                             .arg(name.toHtmlEscaped(), objective.toHtmlEscaped(),
                                  summary.isEmpty() ? QString("No summary.") : summary.toHtmlEscaped(), rows);
    return page(name + " · campaign", body);
}

}
