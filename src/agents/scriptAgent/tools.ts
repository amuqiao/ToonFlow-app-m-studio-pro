import { tool, Tool } from "ai";
import u from "@/utils";
import { z } from "zod";
import _ from "lodash";
import ResTool from "@/socket/resTool";

export const ScriptSchema = z.object({
  name: z.string().describe("剧本名称"),
  content: z.string().describe("剧本内容"),
});
export const planData = z.object({
  storySkeleton: z.string().describe("故事骨架"),
  adaptationStrategy: z.string().describe("改编策略"),
  script: z.array(ScriptSchema).describe("剧本内容"),
});

export type planData = z.infer<typeof planData>;

const keySchema = z.enum(Object.keys(planData.shape) as [keyof planData, ...Array<keyof planData>]);
const planDataKeyLabels = Object.fromEntries(
  Object.entries(planData.shape).map(([key, schema]) => [key, (schema as z.ZodTypeAny).description ?? key]),
) as Record<keyof planData, string>;

interface ToolConfig {
  resTool: ResTool;
  toolsNames?: string[];
  msg: ReturnType<ResTool["newMessage"]>;
}

export default (toolCpnfig: ToolConfig) => {
  const { resTool, toolsNames, msg } = toolCpnfig;

  const ensurePlanRow = async () => {
    const projectId = resTool.data.projectId;
    let row = await u.db("o_agentWorkData").where({ projectId, key: "scriptAgent" }).first();
    if (row) return row;

    const now = Date.now();
    const [id] = await u.db("o_agentWorkData").insert({
      projectId,
      key: "scriptAgent",
      data: JSON.stringify({
        storySkeleton: "",
        adaptationStrategy: "",
      }),
      createTime: now,
      updateTime: now,
    });

    row = await u.db("o_agentWorkData").where({ id }).first();
    return row;
  };

  const readPlanData = async (): Promise<planData> => {
    const row = await ensurePlanRow();
    if (!row) throw new Error("scriptAgent 工作区初始化失败");
    const data = JSON.parse(row?.data ?? "{}");
    const scriptRows = await u.db("o_script").where({ projectId: resTool.data.projectId }).select("id", "name", "content");
    const script = scriptRows
      .filter((item) => item.name && item.content)
      .map((item) => ({
        name: item.name as string,
        content: item.content as string,
      }));

    return {
      storySkeleton: data.storySkeleton ?? "",
      adaptationStrategy: data.adaptationStrategy ?? "",
      script,
    };
  };

  const writePlanField = async (key: "storySkeleton" | "adaptationStrategy", value: string) => {
    const row = await ensurePlanRow();
    if (!row) throw new Error("scriptAgent 工作区初始化失败");
    const data = JSON.parse(row?.data ?? "{}");
    data.storySkeleton = data.storySkeleton ?? "";
    data.adaptationStrategy = data.adaptationStrategy ?? "";
    data[key] = value;

    await u.db("o_agentWorkData").where({ id: row.id }).update({
      data: JSON.stringify(data),
      updateTime: Date.now(),
    });
  };

  const tools: Record<string, Tool> = {
    get_novel_events: tool({
      description: "获取章节事件",
      inputSchema: z.object({
        chapterIndexs: z.array(z.number()).describe("章节的编号"),
      }),
      execute: async ({ chapterIndexs }) => {
        console.log("[tools] get_novel_events", chapterIndexs);
        const thinking = msg.thinking("正在查询章节事件...");
        const data = await u
          .db("o_novel")
          .where("projectId", resTool.data.projectId)
          .select("id", "chapterIndex as index", "reel", "chapter", "chapterData", "event", "eventState")
          .whereIn("chapterIndex", chapterIndexs);
        thinking.appendText("正在查询章节编号: " + chapterIndexs.join(","));
        const eventString = data.map((i: any) => [`第${i.index}章，标题：${i.chapter}，事件：${i.event}`].join("\n")).join("\n");
        thinking.appendText("查询结果:\n" + eventString);
        thinking.updateTitle("查询章节事件完成");
        thinking.complete();
        return eventString ?? "无数据";
      },
    }),
    get_planData: tool({
      description: "获取工作区数据",
      inputSchema: z.object({
        key: keySchema.describe("数据key"),
      }),
      execute: async ({ key }) => {
        console.log("[tools] get_planData", key);
        const thinking = msg.thinking(`正在获取${planDataKeyLabels[key]}工作区数据...`);
        const planData = await readPlanData();
        thinking.appendText(`获取到${planDataKeyLabels[key]}:\n` + planData[key]);
        thinking.updateTitle(`获取${planDataKeyLabels[key]}完成`);
        thinking.complete();
        return planData[key] ?? "无数据";
      },
    }),
    set_planData_storySkeleton: tool({
      description: "写入故事骨架到工作区",
      inputSchema: z.object({
        content: z.string().describe("完整的故事骨架 Markdown 内容"),
      }),
      execute: async ({ content }) => {
        console.log("[tools] set_planData_storySkeleton");
        const thinking = msg.thinking("正在写入故事骨架...");
        await writePlanField("storySkeleton", content);
        thinking.appendText("故事骨架已写入工作区。");
        thinking.updateTitle("保存故事骨架完成");
        thinking.complete();
        return "故事骨架已保存，请在右侧工作台查看。";
      },
    }),
    set_planData_adaptationStrategy: tool({
      description: "写入改编策略到工作区",
      inputSchema: z.object({
        content: z.string().describe("完整的改编策略 Markdown 内容"),
      }),
      execute: async ({ content }) => {
        console.log("[tools] set_planData_adaptationStrategy");
        const thinking = msg.thinking("正在写入改编策略...");
        await writePlanField("adaptationStrategy", content);
        thinking.appendText("改编策略已写入工作区。");
        thinking.updateTitle("保存改编策略完成");
        thinking.complete();
        return "改编策略已保存，请在右侧工作台查看。";
      },
    }),
    get_novel_text: tool({
      description: "获取小说章节原始文本内容",
      inputSchema: z.object({
        chapterIndex: z.string().describe("章节编号"),
      }),
      execute: async ({ chapterIndex }) => {
        console.log("[tools] get_novel_text", "[tools] get_novel_text", chapterIndex);
        const thinking = msg.thinking(`正在获取小说章节原文...`);
        const data = await u.db("o_novel").where("projectId", resTool.data.projectId).where({ chapterIndex }).select("chapterData").first();
        const text = data && data?.chapterData ? data.chapterData : "";
        thinking.appendText(`获取到原文:\n` + text);
        thinking.updateTitle(`获取小说章节原文完成`);
        thinking.complete();
        return text ?? "无数据";
      },
    }),
    insert_script_to_sqlite: tool({
      description: "将剧本写入 SQLite 工作区",
      inputSchema: z.object({
        scripts: z.array(ScriptSchema).describe("需要保存的剧本列表"),
      }),
      execute: async ({ scripts }) => {
        console.log("[tools] insert_script_to_sqlite", scripts.map((s) => s.name));
        const thinking = msg.thinking("正在写入剧本...");
        const projectId = resTool.data.projectId;

        await Promise.all(
          scripts.map(async (script) => {
            const row = await u.db("o_script").where({ projectId, name: script.name }).first();
            if (row) {
              await u.db("o_script").where({ id: row.id }).update({ content: script.content });
            } else {
              await u.db("o_script").insert({ projectId, name: script.name, content: script.content });
            }
          }),
        );

        thinking.appendText(`已写入 ${scripts.length} 份剧本。`);
        thinking.updateTitle("保存剧本完成");
        thinking.complete();
        return "剧本已保存，请在右侧工作台查看。";
      },
    }),
    get_script_content: tool({
      description: "获取剧本本内容",
      inputSchema: z.object({
        ids: z.array(z.string()).describe("脚本id"),
      }),
      execute: async ({ ids }) => {
        console.log("[tools] get_script_content", "[tools] get_script_content", ids);
        const thinking = msg.thinking(`正在获取脚本内容...`);
        const data = await u.db("o_script").whereIn("id", ids).select("content", "name");
        const text = data && data.length ? data.map((d) => `<scriptItem name="${d.name}">${d.content}</scriptItem>`).join("\n") : "";
        thinking.appendText(`获取到脚本内容:\n` + JSON.stringify(data, null, 2));
        thinking.updateTitle(`获取脚本内容完成`);
        thinking.complete();
        return text ?? "无数据";
      },
    }),
  };
  return toolsNames ? Object.fromEntries(Object.entries(tools).filter(([n]) => toolsNames.includes(n))) : tools;
};
