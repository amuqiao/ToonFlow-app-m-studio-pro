/**
 * Toonflow AI供应商模板
 * @version 2.0
 */
// ============================================================
// 类型定义
// ============================================================
type VideoMode =
  | "singleImage"
  | "startEndRequired"
  | "endFrameOptional"
  | "startFrameOptional"
  | "text"
  | (`videoReference:${number}` | `imageReference:${number}` | `audioReference:${number}`)[];
interface TextModel {
  name: string;
  modelName: string;
  type: "text";
  think: boolean;
}
interface ImageModel {
  name: string;
  modelName: string;
  type: "image";
  mode: ("text" | "singleImage" | "multiReference")[];
  associationSkills?: string;
}
interface VideoModel {
  name: string;
  modelName: string;
  type: "video";
  mode: VideoMode[];
  associationSkills?: string;
  audio: "optional" | false | true;
  durationResolutionMap: { duration: number[]; resolution: string[] }[];
}
interface TTSModel {
  name: string;
  modelName: string;
  type: "tts";
  voices: { title: string; voice: string }[];
}
interface VendorConfig {
  id: string;
  version: string;
  name: string;
  author: string;
  description?: string;
  icon?: string;
  inputs: { key: string; label: string; type: "text" | "password" | "url"; required: boolean; placeholder?: string }[];
  inputValues: Record<string, string>;
  models: (TextModel | ImageModel | VideoModel | TTSModel)[];
}
type ReferenceList =
  | { type: "image"; sourceType: "base64"; base64: string }
  | { type: "audio"; sourceType: "base64"; base64: string }
  | { type: "video"; sourceType: "base64"; base64: string };
interface ImageConfig {
  prompt: string;
  referenceList?: Extract<ReferenceList, { type: "image" }>[];
  size: "1K" | "2K" | "4K";
  aspectRatio: `${number}:${number}`;
}
interface VideoConfig {
  duration: number;
  resolution: string;
  aspectRatio: "16:9" | "9:16";
  prompt: string;
  referenceList?: ReferenceList[];
  audio?: boolean;
  mode: VideoMode[];
}
interface TTSConfig {
  text: string;
  voice: string;
  speechRate: number;
  pitchRate: number;
  volume: number;
}
interface PollResult {
  completed: boolean;
  data?: string;
  error?: string;
}
// ============================================================
// 全局声明
// ============================================================
declare const axios: any;
declare const logger: (msg: string) => void;
declare const jsonwebtoken: any;
declare const zipImage: (base64: string, size: number) => Promise<string>;
declare const zipImageResolution: (base64: string, w: number, h: number) => Promise<string>;
declare const mergeImages: (base64Arr: string[], maxSize?: string) => Promise<string>;
declare const urlToBase64: (url: string) => Promise<string>;
declare const pollTask: (fn: () => Promise<PollResult>, interval?: number, timeout?: number) => Promise<PollResult>;
declare const createOpenAI: any;
declare const createDeepSeek: any;
declare const createZhipu: any;
declare const createQwen: any;
declare const createAnthropic: any;
declare const createOpenAICompatible: any;
declare const createXai: any;
declare const createMinimax: any;
declare const createGoogleGenerativeAI: any;
declare const Buffer: any;
declare const exports: {
  vendor: VendorConfig;
  textRequest: (m: TextModel, t: boolean, tl: 0 | 1 | 2 | 3) => any;
  imageRequest: (c: ImageConfig, m: ImageModel) => Promise<string>;
  videoRequest: (c: VideoConfig, m: VideoModel) => Promise<string>;
  ttsRequest: (c: TTSConfig, m: TTSModel) => Promise<string>;
  checkForUpdates?: () => Promise<{ hasUpdate: boolean; latestVersion: string; notice: string }>;
  updateVendor?: () => Promise<string>;
};
// ============================================================
// 供应商配置
// ============================================================
const vendor: VendorConfig = {
  id: "openai",
  version: "2.0",
  author: "Toonflow",
  name: "OpenAI标准接口",
  description: "OpenAI标准格式接口，可修改请求地址并手动添加模型。",
  icon: "",
  inputs: [
    { key: "apiKey", label: "API密钥", type: "password", required: true },
    { key: "baseUrl", label: "请求地址", type: "url", required: true, placeholder: "以v1结束，示例：https://api.openai.com/v1" },
  ],
  inputValues: {
    apiKey: "",
    baseUrl: "https://api.openai.com/v1",
  },
  models: [
    { name: "GPT-4o", modelName: "gpt-4o", type: "text", think: false },
    { name: "GPT-4.1", modelName: "gpt-4.1", type: "text", think: false },
    { name: "GPT-5.1", modelName: "gpt-5.1", type: "text", think: false },
    { name: "GPT-5.2", modelName: "gpt-5.2", type: "text", think: false },
    { name: "GPT-5.4", modelName: "gpt-5.4", type: "text", think: false },
    { name: "GPT Image 1", modelName: "gpt-image-1", type: "image", mode: ["text", "singleImage", "multiReference"] },
    { name: "GPT Image 1 Mini", modelName: "gpt-image-1-mini", type: "image", mode: ["text", "singleImage", "multiReference"] },
    { name: "GPT Image 1.5", modelName: "gpt-image-1.5", type: "image", mode: ["text", "singleImage", "multiReference"] },
    { name: "Sora 2", modelName: "sora-2", type: "video", mode: ["text", "singleImage"], audio: "optional", durationResolutionMap: [{ duration: [4, 8, 12], resolution: ["720p", "1024p"] }] },
    { name: "Sora 2 Pro", modelName: "sora-2-pro", type: "video", mode: ["text", "singleImage"], audio: "optional", durationResolutionMap: [{ duration: [4, 8, 12], resolution: ["720p", "1024p"] }] },
  ],
};
// ============================================================
// 辅助函数
// ============================================================
const getHeaders = (): Record<string, string> => {
  if (!vendor.inputValues.apiKey) throw new Error("缺少API Key");
  return {
    "Content-Type": "application/json",
    Authorization: `Bearer ${vendor.inputValues.apiKey.replace(/^Bearer\s+/i, "")}`,
  };
};

const getBaseUrl = () => vendor.inputValues.baseUrl.replace(/\/+$/, "");

const normalizeDataUrl = (base64: string, fallbackMime = "image/png") => {
  if (!base64) throw new Error("缺少参考文件");
  return base64.startsWith("data:") ? base64 : `data:${fallbackMime};base64,${base64}`;
};

const parseDataUrl = (dataUrl: string, fallbackMime = "application/octet-stream") => {
  const match = dataUrl.match(/^data:([^;]+);base64,(.+)$/);
  if (match) {
    return { mime: match[1], base64: match[2] };
  }
  return { mime: fallbackMime, base64: dataUrl };
};

const inferImageSize = (aspectRatio: string) => {
  const [width = 1, height = 1] = aspectRatio.split(":").map(Number);
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) return "1024x1024";
  if (Math.abs(width - height) < 0.01) return "1024x1024";
  return width > height ? "1536x1024" : "1024x1536";
};

const inferImageQuality = (size: ImageConfig["size"]) => {
  switch (size) {
    case "4K":
      return "high";
    case "2K":
      return "medium";
    default:
      return "low";
  }
};

const extractImageBase64 = async (data: any) => {
  const candidates = Array.isArray(data?.data) ? data.data : [];
  for (const item of candidates) {
    if (item?.b64_json) return `data:image/${data?.output_format || "png"};base64,${item.b64_json}`;
    if (item?.url) return await urlToBase64(item.url);
    if (item?.error) throw new Error(item.error.message || item.error.code || "图片生成失败");
  }
  throw new Error("图片生成失败：未返回有效图片");
};

const mapVideoSize = (aspectRatio: "16:9" | "9:16", resolution: string) => {
  const normalized = resolution.toLowerCase();
  if (normalized === "1024p" || normalized === "1792x1024" || normalized === "1024x1792") {
    return aspectRatio === "16:9" ? "1792x1024" : "1024x1792";
  }
  return aspectRatio === "16:9" ? "1280x720" : "720x1280";
};

const parseVideoSize = (size: string) => {
  const [width, height] = size.split("x").map(Number);
  if (!Number.isFinite(width) || !Number.isFinite(height)) {
    throw new Error(`无效的视频尺寸: ${size}`);
  }
  return { width, height };
};

const normalizeVideoSeconds = (duration: number) => {
  if (duration <= 4) return "4";
  if (duration <= 8) return "8";
  return "12";
};

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

const isRetryableVideoCreateError = (error: any) => {
  const status = error?.response?.status;
  const message = String(error?.response?.data?.error?.message || error?.message || "");
  return status >= 500 || /server had an error processing your request/i.test(message) || /ECONNRESET|ETIMEDOUT|EPIPE/i.test(message);
};

// OpenAI 视频任务创建偶发返回 5xx。这里做小范围重试，避免把单次供应商抖动直接落成失败记录。
const createVideoTaskWithRetry = async (formData: any, maxAttempts = 3) => {
  let lastError: any;
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      return await axios.post(`${getBaseUrl()}/videos`, formData, {
        headers: {
          Authorization: `Bearer ${vendor.inputValues.apiKey.replace(/^Bearer\s+/i, "")}`,
          ...formData.getHeaders(),
        },
      });
    } catch (error: any) {
      lastError = error;
      if (!isRetryableVideoCreateError(error) || attempt === maxAttempts) {
        throw error;
      }
      logger(`[OpenAI] 视频任务创建失败，正在重试 (${attempt}/${maxAttempts})`);
      await wait(attempt * 1500);
    }
  }
  throw lastError;
};

const downloadVideoBase64 = async (videoId: string) => {
  const response = await axios.get(`${getBaseUrl()}/videos/${videoId}/content`, {
    headers: { Authorization: `Bearer ${vendor.inputValues.apiKey.replace(/^Bearer\s+/i, "")}` },
    responseType: "arraybuffer",
  });
  const base64 = Buffer.from(response.data).toString("base64");
  return `data:video/mp4;base64,${base64}`;
};

const buildOpenAIVideoForm = async (config: VideoConfig, model: VideoModel) => {
  const formData = new FormData();
  const targetSize = mapVideoSize(config.aspectRatio, config.resolution);
  formData.append("model", model.modelName);
  formData.append("prompt", config.prompt);
  formData.append("seconds", normalizeVideoSeconds(config.duration));
  formData.append("size", targetSize);

  const imageRefs = (config.referenceList ?? []).filter((item) => item.type === "image");
  if (imageRefs.length > 0) {
    const firstImage = normalizeDataUrl(imageRefs[0].base64, "image/png");
    const { width, height } = parseVideoSize(targetSize);
    const resizedImage = await zipImageResolution(firstImage, width, height);
    const { mime, base64 } = parseDataUrl(resizedImage, "image/jpeg");
    const ext = mime.split("/")[1] || "jpg";
    formData.append("input_reference", Buffer.from(base64, "base64"), {
      filename: `reference.${ext}`,
      contentType: mime,
    });
  }

  return formData;
};

// ============================================================
// 适配器函数
// ============================================================
const textRequest = (model: TextModel, think: boolean, thinkLevel: 0 | 1 | 2 | 3) => {
  if (!vendor.inputValues.apiKey) throw new Error("缺少API Key");
  const apiKey = vendor.inputValues.apiKey.replace(/^Bearer\s+/i, "");
  return createOpenAI({ baseURL: getBaseUrl(), apiKey }).chat(model.modelName);
};
const imageRequest = async (config: ImageConfig, model: ImageModel): Promise<string> => {
  const baseUrl = getBaseUrl();
  const headers = getHeaders();
  const imageRefs = (config.referenceList ?? []).map((item) => ({
    image_url: normalizeDataUrl(item.base64, "image/png"),
  }));

  logger(`[OpenAI] 图片生成请求，模型: ${model.modelName}`);

  if (imageRefs.length > 0) {
    const response = await axios.post(
      `${baseUrl}/images/edits`,
      {
        model: model.modelName,
        prompt: config.prompt,
        images: imageRefs,
        size: inferImageSize(config.aspectRatio),
        quality: inferImageQuality(config.size),
        output_format: "png",
      },
      { headers },
    );
    if (response.data?.error) {
      throw new Error(response.data.error.message || response.data.error.code || "图片编辑失败");
    }
    return await extractImageBase64(response.data);
  }

  const response = await axios.post(
    `${baseUrl}/images/generations`,
    {
      model: model.modelName,
      prompt: config.prompt,
      size: inferImageSize(config.aspectRatio),
      quality: inferImageQuality(config.size),
      output_format: "png",
    },
    { headers },
  );
  if (response.data?.error) {
    throw new Error(response.data.error.message || response.data.error.code || "图片生成失败");
  }
  return await extractImageBase64(response.data);
};
const videoRequest = async (config: VideoConfig, model: VideoModel): Promise<string> => {
  logger(`[OpenAI] 视频生成请求，模型: ${model.modelName}`);

  const formData = await buildOpenAIVideoForm(config, model);
  const createResponse = await createVideoTaskWithRetry(formData);

  const createData = createResponse.data;
  const videoId = createData?.id ?? createData?.data?.[0]?.id;
  if (!videoId) {
    throw new Error("视频生成任务创建失败：未返回任务ID");
  }

  const result = await pollTask(
    async (): Promise<PollResult> => {
      const queryResponse = await axios.get(`${getBaseUrl()}/videos/${videoId}`, {
        headers: {
          Authorization: `Bearer ${vendor.inputValues.apiKey.replace(/^Bearer\s+/i, "")}`,
        },
      });
      const queryData = queryResponse.data;
      switch (queryData?.status) {
        case "completed":
          return { completed: true, data: videoId };
        case "failed":
          return { completed: true, error: queryData?.error?.message || queryData?.last_error?.message || "视频生成失败" };
        case "queued":
        case "in_progress":
          return { completed: false };
        default:
          return { completed: false };
      }
    },
    10000,
    30 * 60 * 1000,
  );

  if (result.error) throw new Error(result.error);
  return await downloadVideoBase64(result.data!);
};
const ttsRequest = async (config: TTSConfig, model: TTSModel): Promise<string> => {
  throw new Error("OpenAI TTS 暂未接入");
};
const checkForUpdates = async (): Promise<{ hasUpdate: boolean; latestVersion: string; notice: string }> => {
  return { hasUpdate: false, latestVersion: "2.0", notice: "" };
};
const updateVendor = async (): Promise<string> => {
  return "";
};
// ============================================================
// 导出
// ============================================================
exports.vendor = vendor;
exports.textRequest = textRequest;
exports.imageRequest = imageRequest;
exports.videoRequest = videoRequest;
exports.ttsRequest = ttsRequest;
exports.checkForUpdates = checkForUpdates;
exports.updateVendor = updateVendor;
export {};
