# Software Design Document: Interconnected Conversations Tool

## Executive Summary

A revolutionary conversation interface that transforms linear AI dialogues into interconnected, graph-based knowledge structures. Users can branch conversations at any point, create context-aware sub-dialogues with different AI models, and navigate their thinking process as a visual network rather than a linear thread.

**Working Title**: ConvoGraph (Conversation Graph Tool)

---

## 1. Problem Statement

### Current Pain Points
1. **Linear Navigation Frustration**: In traditional chat interfaces (ChatGPT, Claude), conversations are strictly linear. When users want to explore a specific part of a response, they must continue the conversation sequentially.

2. **Context Loss**: After 5-6 interaction rounds, finding a specific question/answer requires tedious scrolling and searching through the entire thread.

3. **No Divergent Thinking**: Users cannot explore multiple aspects of a response simultaneously without losing the original context.

4. **Model Lock-in**: Once a conversation starts with a specific model, switching models requires starting a new conversation, losing the original context.

5. **Cognitive Mapping Difficulty**: Complex research or brainstorming sessions don't map well to linear formats; they're naturally hierarchical and interconnected.

---

## 2. Solution Overview

### Core Concept
Transform AI conversations from linear threads into **graph-based dialogue networks** where:
- Each conversation node can spawn child conversations
- Highlighted text becomes context for branching dialogues
- Different AI models can be used at each node
- Visual representation shows the conversation topology
- Navigation is spatial and contextual, not sequential

### Key Innovation
Treating conversations as **connected knowledge nodes** rather than sequential messages, enabling:
- Multi-dimensional exploration of ideas
- Context preservation across branches
- Model-agnostic conversation flow
- Visual knowledge mapping

---

## 3. System Architecture

### 3.1 High-Level Architecture

```
+----------------------------------------------------------+
| Presentation Layer (Frontend)                            |
|  - Canvas renderer (graph view)                          |
|  - Conversation panel (active node)                      |
|  - Service Worker (offline caching, PWA)                 |
+----------------------------------------------------------+
                          |
+----------------------------------------------------------+
| Gateway Layer (API Gateway / Edge)                       |
|  - Authentication & token validation                     |
|  - Rate limiting (per-user, per-tier)                    |
|  - Request routing & load balancing                      |
|  - CORS, CSP headers                                     |
+----------------------------------------------------------+
                          |
+----------------------------------------------------------+
| Application Layer (Business Logic)                       |
|  - Graph manager (nodes/edges, traversal)                |
|  - Model router & orchestrator                           |
|  - WebSocket manager (Socket.io + Redis adapter)         |
+----------------------------------------------------------+
                          |
+----------------------------------------------------------+
| Message Queue Layer (Async Processing)                   |
|  - BullMQ / Redis Streams                                |
|  - AI request queue (priority-based)                     |
|  - Dead letter queue (failed requests)                   |
|  - Background job processing                             |
+----------------------------------------------------------+
                          |
+----------------------------------------------------------+
| Integration Layer (AI Models)                            |
|  - OpenAI / Anthropic / Google / Custom                  |
|  - Provider-specific rate limit handling                 |
|  - Retry logic with exponential backoff                  |
+----------------------------------------------------------+
                          |
+----------------------------------------------------------+
| Data Layer (Persistence)                                 |
|  - PostgreSQL (primary store)                            |
|  - Redis (cache, sessions, pub/sub, queue backend)       |
|  - Object storage (large responses, attachments)         |
+----------------------------------------------------------+
                          |
+----------------------------------------------------------+
| Observability Layer (Cross-cutting)                      |
|  - Structured logging (Pino)                             |
|  - Metrics (Prometheus)                                  |
|  - Distributed tracing (OpenTelemetry)                   |
|  - Error tracking (Sentry)                               |
+----------------------------------------------------------+
```

### 3.2 Message Queue Architecture

AI requests are processed asynchronously to handle rate limits, retries, and provider outages gracefully.

```
User Request → API Server → Queue Job → Worker Pool → AI Provider
                   ↓              ↑
              Immediate ACK    WebSocket/SSE
              (job ID)         (streaming response)
```

**Queue Configuration**:
```typescript
interface AIRequestJob {
  id: string;
  graphId: string;
  nodeId: string;
  userId: string;
  priority: 'high' | 'normal' | 'low';  // Paid users get 'high'
  payload: {
    model: ModelId;
    messages: ChatMessage[];
    parameters?: ModelParameters;
  };
  attempts: number;
  maxAttempts: number;  // Default: 3
  backoff: {
    type: 'exponential';
    delay: number;  // Initial delay in ms
  };
}
```

**Priority Rules**:
- Paid tier users: `high` priority
- Free tier users: `normal` priority
- Regenerate requests: `low` priority (unless paid)

### 3.3 Caching Strategy

```
┌─────────────────────────────────────────────────────────┐
│                    Cache Layers                         │
├─────────────────────────────────────────────────────────┤
│ L1: Browser Cache (Service Worker)                      │
│     - Graph structure (5 min TTL)                       │
│     - Static assets (immutable)                         │
├─────────────────────────────────────────────────────────┤
│ L2: CDN Cache (CloudFlare/CloudFront)                   │
│     - Public graph snapshots (for shared links)         │
│     - API responses with Cache-Control headers          │
├─────────────────────────────────────────────────────────┤
│ L3: Redis Cache (Application)                           │
│     - Graph metadata (10 min TTL)                       │
│     - User session data                                 │
│     - Rate limit counters                               │
│     - AI response cache (opt-in, see below)             │
├─────────────────────────────────────────────────────────┤
│ L4: PostgreSQL (Source of Truth)                        │
│     - All persistent data                               │
└─────────────────────────────────────────────────────────┘
```

**AI Response Caching Rules**:
- Only cache when `temperature = 0` (deterministic)
- Cache key: `hash(model + messages + parameters)`
- Per-user isolation (never share cached responses across users)
- Max TTL: 24 hours
- User can disable via preference

### 3.4 Core Components

#### 3.4.1 Graph Manager
**Responsibilities**:
- Create, read, update, delete conversation nodes
- Maintain node/edge relationships (spawn edges + optional links)
- Track highlighted context anchors for branch creation
- Manage node metadata (timestamps, models used, etc.)

**Key Methods**:
```typescript
interface GraphManager {
  createGraph(title?: string): ConversationGraph
  createRootNode(graphId: string, initialPrompt: string, model: ModelId): ConversationNode
  createChildNode(params: {
    graphId: string
    parentId: string
    anchor: TextAnchor
    prompt: string
    model: ModelId
  }): ConversationNode
  getGraph(graphId: string): ConversationGraph
  getNode(graphId: string, nodeId: string): ConversationNode
  getChildren(graphId: string, nodeId: string): ConversationNode[]
  getAncestryChain(graphId: string, nodeId: string): ConversationNode[]
  deleteNode(graphId: string, nodeId: string, opts?: { cascade?: boolean }): void
  updateNode(graphId: string, nodeId: string, updates: Partial<ConversationNode>): ConversationNode
}
```

#### 3.4.2 Model Router & Orchestrator
**Responsibilities**:
- Route requests to appropriate AI model APIs
- Handle API key management
- Implement rate limiting and retry logic
- Aggregate responses from different models
- Stream responses in real-time

**Supported Models** (Initial):
- OpenAI (configurable model catalog)
- Anthropic (configurable model catalog)
- Google (configurable model catalog)
- Custom/Local models (via OpenAI-compatible APIs)

**Model identifiers**:
- All selected models are stored as `ModelId` (`provider:model`), e.g. `openai:gpt-4o`.
- The enabled model catalog is server-configured and tier-gated (so the UI and pricing tiers don’t depend on hard-coded vendor names).

#### 3.4.3 Canvas Renderer
**Responsibilities**:
- Render conversation graph visually
- Handle node positioning (auto-layout algorithms)
- Implement zoom, pan, and navigation controls
- Highlight active conversation path
- Render node previews

**Rendering Approach**:
- **Library**: React Flow (graph interaction + rendering)
- **Optional**: D3.js for layout computations only (not as the primary renderer)
- **Layout Algorithms**:
  - Hierarchical (for tree-like structures)
  - Force-directed (for complex networks)
  - Manual positioning (user override)

#### 3.4.4 Conversation Panel
**Responsibilities**:
- Display full conversation for selected node
- Show ancestry context (breadcrumb trail)
- Enable text highlighting and annotation
- Provide model selection interface
- Handle user input and submission

---

## 4. Data Models

### 4.0 Definitions & Invariants (MVP)

**Graph shape**:
- MVP uses a **rooted tree**: each node has exactly one `parentId` (except root).
- Post-MVP, we can add **non-tree links** (cross-references) and/or merge edges. This is modeled as additional edge types, without changing the core spawn-tree invariant unless explicitly enabled per graph.
- **Maximum children per node**: 50 (prevents accidental runaway branching)
- **Maximum graph depth**: 100 levels (prevents infinite recursion)

**Selection anchoring**:
- A branch is created from a **text anchor** inside the parent node's AI response.
- **Primary anchor**: The `exact` string is the authoritative anchor. Offsets are optimization hints only.
- Offsets, when present, are defined against the exact stored source string (`response.textMarkdown`) using UTF-16 code unit offsets (browser-native indexing).
- **Validation**: Backend validates anchors by checking `exact` matches at the specified position. If offset-based lookup fails, fall back to substring search for `exact`.
- To tolerate minor formatting edits, store a quote-style selector (`prefix`/`exact`/`suffix`) in addition to offsets.

**Conversation model**:
- Each node represents a **single exchange**: one user prompt → one AI response.
- Multi-turn conversations are modeled as **linear chains of nodes** (each follow-up creates a child node).
- This ensures every exchange is individually addressable for branching.

**Concurrency control**:
- All mutable entities use **optimistic locking** via a `version` field.
- Updates must include the current `version`; mismatches return `409 Conflict`.
- Clients should retry with fresh data on conflict.

### 4.1 Conversation Node

```typescript
type AIProvider = 'openai' | 'anthropic' | 'google' | 'custom'
type ModelId = `${AIProvider}:${string}` // e.g., "openai:gpt-4o", "anthropic:claude-sonnet"

interface ChatMessage {
  role: 'system' | 'user' | 'assistant'
  content: string
}

interface TextAnchor {
  exact: string
  startOffset?: number
  endOffset?: number
  prefix?: string
  suffix?: string
}

interface ConversationNode {
  id: string
  graphId: string
  parentId: string | null
  version: number  // Optimistic locking - increment on every update

  createdAt: string // ISO timestamp
  updatedAt: string // ISO timestamp

  request: {
    userPrompt: string
    // Persist the exact messages sent to the provider for reproducibility/debugging.
    messages: ChatMessage[]
    model: ModelId
    parameters?: {
      temperature?: number
      maxOutputTokens?: number
    }
  }

  response: {
    textMarkdown: string
    finishReason?: 'stop' | 'length' | 'content_filter' | 'error'
    // For regeneration history (optional, post-MVP)
    previousVersions?: Array<{
      textMarkdown: string
      generatedAt: string
      model: ModelId
    }>
  }

  spawnedFrom?: {
    sourceNodeId: string
    anchor: TextAnchor
  }

  usage?: {
    inputTokens?: number
    outputTokens?: number
    costUsd?: number
    durationMs?: number  // Time to first token + total generation time
  }

  annotations: {
    tags: string[]
    notes?: string
    starred: boolean
  }

  // Status tracking for async processing
  status: 'pending' | 'streaming' | 'completed' | 'failed' | 'cancelled'
  error?: {
    code: string
    message: string
    retryable: boolean
  }
}

// Per-user view/layout state is stored separately (important for collaboration).
interface GraphViewState {
  graphId: string
  userId: string
  viewport: { x: number; y: number; zoom: number }
  nodePositions: Record<string, { x: number; y: number }>
  collapsedNodeIds: string[]
  updatedAt: string // ISO timestamp
}
```

### 4.2 Conversation Graph

```typescript
interface ConversationGraph {
  id: string
  title: string
  rootNodeId: string
  version: number  // Optimistic locking

  createdAt: string // ISO timestamp
  updatedAt: string // ISO timestamp

  // Statistics (computed, cached)
  stats: {
    nodeCount: number
    maxDepth: number
    totalTokens?: number
    totalCostUsd?: number
  }

  tags: string[]
  folderId?: string

  sharing: {
    visibility: 'private' | 'link-view' | 'invite-only'
    shareId?: string // random, unguessable token (min 128-bit entropy)
  }

  collaborators?: Array<{
    userId: string
    role: 'owner' | 'editor' | 'viewer'
    addedAt: string // ISO timestamp
  }>

  settings: {
    defaultModel?: ModelId
    allowedModels?: ModelId[]  // Restrict which models can be used
    maxNodesPerBranch?: number  // Override default 50
  }
}

// API response shape - nodes loaded separately for performance
interface ConversationGraphResponse {
  graph: Omit<ConversationGraph, 'nodesById'>

  // Phase 1: Structure only (fast load)
  structure: {
    nodeIds: string[]
    edges: GraphEdge[]
    nodeMetadata: Record<string, {
      id: string
      parentId: string | null
      model: ModelId
      status: ConversationNode['status']
      createdAt: string
      hasChildren: boolean
      childCount: number
      promptPreview: string  // First 100 chars of userPrompt
    }>
  }

  // Phase 2: Full content (loaded on demand)
  // Use GET /api/graphs/:graphId/nodes/:nodeId for full node content
}

interface GraphEdge {
  id: string
  graphId: string
  type: 'spawned_from' | 'link'
  fromNodeId: string
  toNodeId: string
  anchor?: TextAnchor
  createdAt: string // ISO timestamp
}
```

### 4.3 Database Schema

#### Primary Store (PostgreSQL) - MVP source of truth

For MVP, keep **one authoritative store** to avoid dual-write consistency problems.

**Tables (conceptual)**:
- `graphs`: graph metadata + ownership
- `nodes`: node request/response + metadata
- `edges`: relationships (`spawned_from` for the tree, optional `link` for cross-references)
- `graph_view_states`: per-user layout (positions/collapsed/viewport)
- `graph_collaborators`: user roles per graph
- `graph_shares`: link-share tokens + permissions
- `audit_logs`: security-relevant events (MVP requirement)

**Schema Definition**:
```sql
-- Core tables
CREATE TABLE graphs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id),
  title VARCHAR(200) NOT NULL,
  root_node_id UUID,  -- Set after first node created
  version INTEGER NOT NULL DEFAULT 1,
  settings JSONB NOT NULL DEFAULT '{}',
  stats JSONB NOT NULL DEFAULT '{"nodeCount": 0, "maxDepth": 0}',
  sharing JSONB NOT NULL DEFAULT '{"visibility": "private"}',
  tags TEXT[] NOT NULL DEFAULT '{}',
  folder_id UUID REFERENCES folders(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ  -- Soft delete
);

CREATE TABLE nodes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  graph_id UUID NOT NULL REFERENCES graphs(id) ON DELETE CASCADE,
  parent_id UUID REFERENCES nodes(id),
  version INTEGER NOT NULL DEFAULT 1,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  request JSONB NOT NULL,
  response JSONB,
  spawned_from JSONB,
  usage JSONB,
  annotations JSONB NOT NULL DEFAULT '{"tags": [], "starred": false}',
  error JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE edges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  graph_id UUID NOT NULL REFERENCES graphs(id) ON DELETE CASCADE,
  type VARCHAR(20) NOT NULL CHECK (type IN ('spawned_from', 'link')),
  from_node_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  to_node_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  anchor JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id),
  action VARCHAR(50) NOT NULL,
  resource_type VARCHAR(50) NOT NULL,
  resource_id UUID NOT NULL,
  details JSONB,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for common query patterns
CREATE INDEX idx_graphs_user_updated ON graphs(user_id, updated_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_graphs_folder ON graphs(folder_id) WHERE folder_id IS NOT NULL;
CREATE INDEX idx_graphs_sharing ON graphs((sharing->>'shareId')) WHERE sharing->>'shareId' IS NOT NULL;

CREATE INDEX idx_nodes_graph_parent ON nodes(graph_id, parent_id);
CREATE INDEX idx_nodes_graph_created ON nodes(graph_id, created_at DESC);
CREATE INDEX idx_nodes_graph_status ON nodes(graph_id, status) WHERE status != 'completed';
CREATE INDEX idx_nodes_starred ON nodes(graph_id) WHERE (annotations->>'starred')::boolean = true;

CREATE INDEX idx_edges_graph_type ON edges(graph_id, type);
CREATE INDEX idx_edges_from ON edges(from_node_id);
CREATE INDEX idx_edges_to ON edges(to_node_id);

CREATE INDEX idx_audit_logs_user ON audit_logs(user_id, created_at DESC);
CREATE INDEX idx_audit_logs_resource ON audit_logs(resource_type, resource_id, created_at DESC);

-- Full-text search on node content
CREATE INDEX idx_nodes_fts ON nodes USING GIN (
  to_tsvector('english',
    COALESCE(request->>'userPrompt', '') || ' ' ||
    COALESCE(response->>'textMarkdown', '')
  )
);

-- Tree constraint: non-root nodes must have exactly one parent
CREATE UNIQUE INDEX idx_nodes_tree_constraint ON nodes(id)
  WHERE parent_id IS NULL;  -- Only one root per subtree allowed

-- Prevent circular references (enforced in application layer for complex cases)
```

**Connection Pool Configuration**:
```typescript
const pool = new Pool({
  host: process.env.DB_HOST,
  database: process.env.DB_NAME,
  max: 20,                    // Max connections per instance
  min: 5,                     // Keep warm connections
  idleTimeoutMillis: 30000,   // Close idle connections after 30s
  connectionTimeoutMillis: 5000,  // Fail fast on connection issues
  statement_timeout: 30000,   // Query timeout 30s
});
```

**Notes**:
- Large text fields (`response.textMarkdown`) live in `nodes`. For responses > 100KB, consider object storage (S3/GCS) with pointer in JSONB.
- Tree invariants are enforced with constraints + application-layer validation.
- Use `FOR UPDATE SKIP LOCKED` for queue-like operations to prevent contention.

#### Optional Read-Optimized Graph Store (Neo4j) - Post-MVP

If traversal/query needs outgrow PostgreSQL, maintain a **derived** Neo4j representation for fast graph analytics. In that case:
- PostgreSQL remains the source of truth.
- Neo4j is updated asynchronously from the edge stream (event-driven), with backfill tooling.
This avoids inconsistency bugs caused by synchronous dual writes.

### 4.4 Input Validation Schema

All user inputs must be validated against these constraints:

```typescript
const ValidationLimits = {
  // Graph
  graphTitle: { minLength: 1, maxLength: 200 },
  graphTags: { maxCount: 20, maxTagLength: 50 },

  // Node
  userPrompt: { minLength: 1, maxLength: 100_000 },  // ~25K tokens
  annotationNotes: { maxLength: 10_000 },
  annotationTags: { maxCount: 10, maxTagLength: 50 },

  // TextAnchor
  anchorExact: { minLength: 1, maxLength: 10_000 },
  anchorPrefix: { maxLength: 200 },
  anchorSuffix: { maxLength: 200 },

  // Limits
  maxNodesPerGraph: 2000,
  maxChildrenPerNode: 50,
  maxGraphDepth: 100,
  maxGraphsPerUser: {
    free: 5,
    pro: 'unlimited',
    team: 'unlimited'
  }
} as const;

// Character allowlists
const AllowedCharacters = {
  tags: /^[a-zA-Z0-9\-_\s]+$/,  // Alphanumeric, dash, underscore, space
  title: /^[\p{L}\p{N}\p{P}\p{S}\s]+$/u,  // Unicode letters, numbers, punctuation
};
```

---

## 5. User Flows

### 5.1 Creating a Root Conversation

1. User clicks "New Conversation"
2. System displays model selection dropdown
3. User types initial prompt
4. System creates root node and sends request to selected AI model
5. Response streams into conversation panel
6. Node appears on canvas at center position

### 5.2 Branching a Conversation

1. User selects text in current conversation (highlight)
2. Context menu appears with "Branch Conversation" option
3. User clicks "Branch Conversation"
4. New conversation panel opens:
   - Shows highlighted text as context
   - Displays model selector (defaults to parent's model)
   - Provides input field for new prompt
5. User enters prompt and submits
6. System creates child node linked to parent
7. Canvas updates to show new connection
8. User can toggle between parent and child views

### 5.3 Navigating the Graph

**Canvas Navigation**:
- **Zoom**: Mouse wheel or pinch gesture
- **Pan**: Click and drag background
- **Select Node**: Click node to open in conversation panel
- **Hover Node**: Shows preview tooltip

**Conversation Panel Navigation**:
- **Breadcrumb Trail**: Shows path from root (clickable)
- **Parent Button**: Jump to parent node
- **Children List**: Sidebar showing all child branches
- **Search**: Full-text search across all nodes

### 5.4 Switching Models Mid-Graph

1. User creates branch from existing node
2. In model selector, chooses different model (e.g., GPT-4 -> Claude Sonnet)
3. System sends highlighted context + new prompt to new model
4. Response generated with new model
5. Node metadata stores model change
6. Visual indicator shows model switch (color coding or icon)

---

## 6. Technical Specifications

### 6.1 Frontend Stack

**Framework**: React 18+ with TypeScript
**State Management**: Zustand or Redux Toolkit
**Graph Visualization**: React Flow (primary)
**UI Components**: Shadcn UI or Chakra UI
**Styling**: Tailwind CSS
**Rich Text Editor**: TipTap or Lexical (for highlighting)

### 6.2 Backend Stack

**Runtime**: Node.js with Express or Fastify
**Language**: TypeScript
**Primary Store (MVP)**: PostgreSQL (JSONB for flexible node payloads)
**Optional (Post-MVP)**: Neo4j as a read-optimized derived store for analytics/traversals
**Caching**: Redis
**Real-time**: WebSockets (Socket.io)

### 6.3 AI Model Integration

**API Clients**:
- OpenAI SDK
- Anthropic SDK
- Google Generative AI SDK
- Axios for custom endpoints

**Features**:
- Streaming responses
- Token counting
- Error handling and retries
- Rate limiting per provider
- Cost tracking

### 6.4 Deployment

**Frontend**: Vercel, Netlify, or AWS Amplify
**Backend**: AWS ECS/Fargate, Google Cloud Run, or Railway
**Database**:
  - Managed PostgreSQL (primary)
  - Redis (optional, but recommended for caching/rate-limit buckets)
  - Neo4j Aura (optional, post-MVP, derived store)
**CDN**: CloudFlare or AWS CloudFront

---

## 7. Feature Specifications

### 7.1 Core Features (MVP)

#### F1: Text Highlighting & Context Extraction
- **Description**: Users can highlight any portion of AI response
- **Implementation**:
  - Store a `TextAnchor` (exact text + optional offsets + prefix/suffix) against `response.textMarkdown`
  - Preserve formatting (markdown/code blocks) by anchoring against the stored markdown string, not the rendered DOM
  - Show highlighted text in child node context panel

#### F2: Model Selection Per Node
- **Description**: Choose different AI model for each conversation branch
- **Models Supported**: Configurable model catalog (tier-gated). Examples: `openai:*`, `anthropic:*`, `google:*`
- **UI**: Dropdown with model name, provider icon, and cost indicator

#### F3: Graph Visualization
- **Description**: Visual canvas showing conversation network
- **Layout**: Hierarchical tree with automatic positioning
- **Interactions**: Zoom, pan, node selection, collapse/expand

#### F4: Conversation Panel
- **Description**: Full conversation view for selected node
- **Components**:
  - Breadcrumb navigation
  - Parent context display (if applicable)
  - User prompt
  - AI response (markdown rendered)
  - Input field for new prompt or branching

#### F5: Node Persistence
- **Description**: Save and load conversation graphs
- **Storage**: Cloud-based with unique shareable URLs
- **Auto-save**: Every 30 seconds or on node creation

### 7.2 Advanced Features (Post-MVP)

#### F6: Collaborative Conversations
- **Description**: Multiple users can contribute to same graph
- **Features**:
  - Real-time cursor presence
  - Branch ownership/attribution
  - Commenting on nodes

#### F7: Export & Import
- **Formats**:
  - JSON (full graph data)
  - Markdown (linear transcript)
  - PDF (visual diagram + content)
  - Obsidian-compatible format

#### F8: Search & Filters
- **Search**:
  - Full-text across all nodes
  - Filter by model, date, tags
  - Regex support
- **Highlight**: Matching nodes in graph view

#### F9: Templates & Presets
- **Description**: Pre-configured conversation flows
- **Examples**:
  - "Research Deep-Dive" (question -> 3 model comparison branches)
  - "Debate Mode" (multiple models respond to same prompt)
  - "Translation Chain" (sequential model prompts)

#### F10: Analytics Dashboard
- **Metrics**:
  - Total tokens used per graph
  - Cost breakdown by model
  - Conversation depth statistics
  - Most branched nodes

#### F11: AI-Assisted Graph Optimization
- **Features**:
  - Suggest merge points for similar branches
  - Identify redundant conversations
  - Recommend next prompts based on context

---

## 8. User Interface Design

### 8.1 Layout Structure

```
+--------------------------------------------------------+
| Header: Logo | Graph Title | [Save] [Share] [Settings] |
+----------------------+---------------------------------+
| Canvas View           | Conversation Panel              |
| (Graph Network)       |                                 |
|                       | [Breadcrumb: Root > Node2]       |
|   [Root]              | Parent Context:                  |
|     |                 | "... highlighted text ..."       |
|  [Node1] [Node2]      | -------------------------------- |
|        |              | Conversation                     |
|      [Node3]          | User: [prompt]                   |
|                       | AI:   [response w/ highlighting] |
| [Minimap]             | -------------------------------- |
|                       | New Input                        |
|                       | [Model Selector] [Text Input]    |
|                       | [Submit] [Branch]                |
+----------------------+---------------------------------+
```

### 8.2 Visual Design Principles

**Color Coding**:
- Each model has distinct color (OpenAI: green, Claude: purple, Gemini: blue)
- Node borders use model color
- Edges use parent model color

**Node States**:
- **Active**: Bold border, full opacity
- **Inactive**: Thin border, 70% opacity
- **Collapsed**: Small thumbnail with child count badge
- **Loading**: Pulsing animation

**Responsiveness**:
- Desktop: Side-by-side canvas + panel
- Tablet: Swipeable panels with tab bar
- Mobile: Fullscreen mode with bottom sheet for graph view

---

## 9. API Design

### 9.1 REST Endpoints

#### Graph Operations
```
POST   /api/graphs                          # Create graph (optionally create root node)
GET    /api/graphs                          # List current user's graphs (cursor pagination)
GET    /api/graphs/:graphId                 # Get graph structure (two-phase: metadata + structure)
GET    /api/graphs/:graphId/full            # Get graph with all node content (small graphs only)
PUT    /api/graphs/:graphId                 # Update graph metadata (title/tags/folder)
DELETE /api/graphs/:graphId                 # Soft delete graph

GET    /api/graphs/:graphId/export?format=json|md|pdf
POST   /api/graphs/:graphId/share           # Create/revoke share link
GET    /api/shares/:shareId                 # Read-only access via share token (when enabled)

POST   /api/graphs/:graphId/duplicate       # Clone graph (with or without responses)
POST   /api/graphs/import                   # Import from JSON/external format
```

#### Node Operations
```
POST   /api/graphs/:graphId/nodes                 # Create node (root if parentId is null/omitted)
GET    /api/graphs/:graphId/nodes/:nodeId         # Get full node content
PUT    /api/graphs/:graphId/nodes/:nodeId         # Update node (annotations, etc.)
DELETE /api/graphs/:graphId/nodes/:nodeId         # Delete node (with cascade option)

POST   /api/graphs/:graphId/nodes/:nodeId/regenerate  # Re-run AI with same/different model
POST   /api/graphs/:graphId/nodes/:nodeId/cancel      # Cancel in-progress generation
GET    /api/graphs/:graphId/nodes/:nodeId/children?cursor=X&limit=20
GET    /api/graphs/:graphId/nodes/:nodeId/ancestry
```

#### Batch Operations
```
POST   /api/graphs/:graphId/nodes/batch     # Create multiple nodes
DELETE /api/graphs/:graphId/nodes/batch     # Delete multiple nodes (subtrees)
PUT    /api/graphs/:graphId/nodes/batch     # Update multiple nodes (annotations)
POST   /api/graphs/:graphId/move            # Move subtree to different parent
```

#### Search Operations
```
GET    /api/graphs/:graphId/search?q=term&filters=...  # Search within graph
GET    /api/search?q=term&graphIds=...                  # Search across graphs
```

**Request/Response Examples**:

**Create Node Request**:
```json
{
  "parentId": "node-uuid-or-null",
  "prompt": "What does this paragraph mean?",
  "model": "openai:gpt-4o",
  "anchor": {
    "exact": "highlighted text",
    "startOffset": 123,
    "endOffset": 141,
    "prefix": "some text before",
    "suffix": "some text after"
  },
  "parameters": {
    "temperature": 0.7,
    "maxOutputTokens": 4096
  },
  "stream": true,
  "clientRequestId": "uuid-for-idempotency"
}
```

**Create Node Response** (immediate):
```json
{
  "node": {
    "id": "new-node-uuid",
    "graphId": "graph-uuid",
    "parentId": "parent-uuid",
    "version": 1,
    "status": "pending",
    "request": { ... },
    "response": null,
    "createdAt": "2026-02-03T10:00:00Z",
    "updatedAt": "2026-02-03T10:00:00Z"
  },
  "jobId": "queue-job-uuid"
}
```

**Regenerate Request**:
```json
{
  "model": "anthropic:claude-sonnet",
  "preserveHistory": true,
  "clientRequestId": "uuid"
}
```

**Regenerate Behavior**:
- If `preserveHistory: true`: Old response moved to `response.previousVersions[]`, new response replaces current
- If `preserveHistory: false`: Old response discarded, new response replaces current
- Children of the node are **preserved** (they reference the node ID, not the response content)
- Orphaned children warning returned if new response significantly differs

**Batch Delete Request**:
```json
{
  "nodeIds": ["node-1", "node-2"],
  "cascade": true,
  "clientRequestId": "uuid"
}
```

**Paginated Children Response**:
```json
{
  "children": [ ... ],
  "pagination": {
    "cursor": "encoded-cursor",
    "hasMore": true,
    "total": 47
  }
}
```

**Update with Optimistic Locking**:
```json
PUT /api/graphs/:graphId/nodes/:nodeId
{
  "version": 3,
  "annotations": {
    "tags": ["important"],
    "starred": true
  }
}
```

**Conflict Response** (409):
```json
{
  "error": "CONFLICT",
  "message": "Node was modified. Expected version 3, found 4.",
  "currentVersion": 4,
  "currentData": { ... }
}
```

### 9.2 WebSocket Events

**Connection Setup**:
```typescript
// Client connects with auth token
const socket = io('/graphs', {
  auth: { token: accessToken },
  transports: ['websocket'],  // Skip long-polling
});

// Server uses Redis adapter for horizontal scaling
import { createAdapter } from '@socket.io/redis-adapter';
io.adapter(createAdapter(pubClient, subClient));
```

**Event Definitions**:
```typescript
// ─────────────────────────────────────────────────────────
// Client -> Server Events
// ─────────────────────────────────────────────────────────

interface ClientEvents {
  // Subscription management
  'graph:subscribe': { graphId: string };
  'graph:unsubscribe': { graphId: string };

  // Node operations (prefer REST for reliability, WS for real-time)
  'node:create': {
    graphId: string;
    parentId: string | null;
    prompt: string;
    model: ModelId;
    anchor?: TextAnchor;
    clientRequestId: string;
  };
  'node:cancel': { nodeId: string };
  'node:update': {
    nodeId: string;
    version: number;
    updates: Partial<Pick<ConversationNode, 'annotations'>>;
  };

  // Collaboration presence
  'presence:update': {
    graphId: string;
    cursor?: { nodeId: string; position?: number };
    selection?: { nodeId: string; anchor: TextAnchor };
  };

  // Heartbeat
  'ping': { timestamp: number };
}

// ─────────────────────────────────────────────────────────
// Server -> Client Events
// ─────────────────────────────────────────────────────────

interface ServerEvents {
  // Connection
  'connect:ack': { userId: string; serverTime: string };
  'error': { code: string; message: string; retryable: boolean };

  // Node lifecycle
  'node:created': { node: ConversationNode };
  'node:updated': { nodeId: string; version: number; updates: Partial<ConversationNode> };
  'node:deleted': { nodeId: string; cascade: boolean; deletedNodeIds: string[] };

  // AI streaming
  'ai:queued': { nodeId: string; position: number; estimatedWaitMs?: number };
  'ai:started': { nodeId: string; model: ModelId };
  'ai:chunk': { nodeId: string; chunk: string; index: number };
  'ai:complete': {
    nodeId: string;
    response: ConversationNode['response'];
    usage: ConversationNode['usage'];
  };
  'ai:error': {
    nodeId: string;
    error: { code: string; message: string; retryable: boolean };
  };
  'ai:cancelled': { nodeId: string };

  // Collaboration (post-MVP)
  'user:joined': { userId: string; userName: string; avatarUrl?: string };
  'user:left': { userId: string };
  'user:presence': {
    userId: string;
    cursor?: { nodeId: string; position?: number };
    selection?: { nodeId: string; anchor: TextAnchor };
  };

  // Graph-level events
  'graph:updated': { graphId: string; version: number; updates: Partial<ConversationGraph> };

  // Heartbeat
  'pong': { timestamp: number; serverTime: string };
}
```

**Error Codes**:
```typescript
const WebSocketErrorCodes = {
  // Authentication
  AUTH_REQUIRED: 'Authentication required',
  AUTH_EXPIRED: 'Token expired, please reconnect',
  AUTH_INVALID: 'Invalid authentication token',

  // Authorization
  FORBIDDEN: 'Not authorized for this graph',
  READONLY: 'Graph is read-only for this user',

  // Rate limiting
  RATE_LIMITED: 'Too many requests, slow down',
  QUEUE_FULL: 'AI request queue is full, try again later',

  // Validation
  INVALID_PAYLOAD: 'Invalid request payload',
  NODE_NOT_FOUND: 'Node does not exist',
  GRAPH_NOT_FOUND: 'Graph does not exist',

  // Conflicts
  VERSION_CONFLICT: 'Version conflict, refresh and retry',

  // Provider errors
  PROVIDER_ERROR: 'AI provider error',
  PROVIDER_UNAVAILABLE: 'AI provider temporarily unavailable',
  PROVIDER_RATE_LIMITED: 'AI provider rate limit hit',
} as const;
```

---

## 10. Security & Privacy

### 10.1 Authentication
- **Methods**: OAuth 2.0 (Google, GitHub) and Email/Password (with email verification)
- **Password Storage**: Argon2id (cost=3, memory=64MB, parallelism=1) + per-user salt
- **Session Model**:
  - Short-lived access token (JWT, ~15 min, signed with RS256)
  - Rotating refresh token (HTTP-only, Secure, SameSite=Strict cookie, ~30 days) with server-side revocation
  - Refresh token rotation: new token issued on each refresh, old token invalidated
- **Account Linking**: Users can link OAuth identities to an existing email account (explicit consent flow)
- **MFA**: Optional TOTP-based 2FA for paid tiers (post-MVP)

### 10.2 Authorization
- **Roles**: `owner`, `editor`, `viewer`
- **Graph Ownership**: Creator is `owner` by default and can manage collaborators/shares
- **Share Links**:
  - Link access uses an unguessable `shareId` token (min 128-bit entropy, URL-safe base64)
  - Default is read-only (`link-view`) and can be revoked at any time
  - Rate limit on share link access: 100 requests/minute per IP to prevent enumeration
- **Permission Checks**: Every graph/node API call is authorized by `(userId, graphId, role)`; never by client-supplied `userId`
- **Row-Level Security**: PostgreSQL RLS policies enforce authorization at database level as defense-in-depth

### 10.3 Content Security

#### 10.3.1 Content Security Policy (CSP)
```http
Content-Security-Policy:
  default-src 'self';
  script-src 'self' 'strict-dynamic';
  style-src 'self' 'unsafe-inline';
  img-src 'self' data: https:;
  connect-src 'self' wss://*.convograph.app https://api.openai.com https://api.anthropic.com;
  frame-ancestors 'none';
  base-uri 'self';
  form-action 'self';
```

#### 10.3.2 Markdown Sanitization (XSS Prevention)
AI responses contain markdown that must be sanitized before rendering:

```typescript
import DOMPurify from 'dompurify';
import { marked } from 'marked';

const ALLOWED_TAGS = [
  'p', 'br', 'strong', 'em', 'code', 'pre', 'blockquote',
  'ul', 'ol', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'a', 'img', 'table', 'thead', 'tbody', 'tr', 'th', 'td',
  'hr', 'del', 'sup', 'sub', 'span', 'div'
];

const ALLOWED_ATTR = [
  'href', 'src', 'alt', 'title', 'class', 'id',
  'target', 'rel', 'colspan', 'rowspan'
];

function sanitizeMarkdown(markdown: string): string {
  const html = marked.parse(markdown);
  return DOMPurify.sanitize(html, {
    ALLOWED_TAGS,
    ALLOWED_ATTR,
    ALLOW_DATA_ATTR: false,
    ADD_ATTR: ['target'],  // For links
    FORBID_TAGS: ['script', 'style', 'iframe', 'object', 'embed'],
    FORBID_ATTR: ['onerror', 'onload', 'onclick', 'onmouseover'],
  });
}

// Additional: sanitize href to prevent javascript: URLs
DOMPurify.addHook('afterSanitizeAttributes', (node) => {
  if (node.hasAttribute('href')) {
    const href = node.getAttribute('href') || '';
    if (!href.startsWith('http://') && !href.startsWith('https://') && !href.startsWith('/')) {
      node.removeAttribute('href');
    }
  }
});
```

#### 10.3.3 Code Block Rendering
Code blocks require additional isolation:
- Syntax highlighting via Prism.js or Shiki (no eval)
- No automatic script execution in code blocks
- Optional: Render code in sandboxed iframe for copy-paste safety

### 10.4 Data Privacy
- **API Keys**: Encrypted at rest (AES-256-GCM) with per-environment KMS-managed master key; decrypted only in memory for outbound requests
- **Bring Your Own Key (BYOK)**:
  - Stored server-side (encrypted) and scoped per user/workspace
  - Never returned in plaintext after initial entry (masked display: `sk-...xxxx`)
  - Used only for that user's requests (no cross-user caching/sharing)
  - Key rotation: Users can rotate keys; old key invalidated immediately
  - Audit trail: All API key usage logged with timestamp, model, token count
- **Data Retention (Hosted SaaS)**:
  - Free tier: 7-day retention (active + deleted)
  - Paid tiers: Indefinite until deleted
  - Paid tiers deletion: 30-day soft delete, then permanent removal
- **GDPR Compliance**:
  - Data export: `GET /api/users/me/export` returns all user data in JSON
  - Account deletion: `DELETE /api/users/me` triggers full data purge within 30 days
  - Data portability: Export includes all graphs, nodes, and metadata

### 10.5 Rate Limiting

```typescript
const RateLimits = {
  // Per-user limits (token bucket)
  user: {
    free: {
      requests: { rate: 60, per: 'minute' },
      aiRequests: { rate: 10, per: 'minute' },
      nodeCreation: { rate: 30, per: 'hour' },
    },
    pro: {
      requests: { rate: 300, per: 'minute' },
      aiRequests: { rate: 60, per: 'minute' },
      nodeCreation: { rate: 200, per: 'hour' },
    },
    team: {
      requests: { rate: 600, per: 'minute' },
      aiRequests: { rate: 120, per: 'minute' },
      nodeCreation: { rate: 500, per: 'hour' },
    },
  },

  // Per-graph limits (prevent runaway)
  graph: {
    nodeCreation: { rate: 20, per: 'minute' },  // Burst protection
  },

  // Per-IP limits (unauthenticated)
  ip: {
    auth: { rate: 10, per: 'minute' },  // Login/signup attempts
    shareAccess: { rate: 100, per: 'minute' },  // Share link access
  },

  // Per-provider limits (respect upstream quotas)
  provider: {
    openai: { tokensPerMinute: 90000 },  // Varies by tier
    anthropic: { tokensPerMinute: 100000 },
    google: { tokensPerMinute: 60000 },
  },
};
```

### 10.6 Audit Logging

Security-relevant events logged to `audit_logs` table:

```typescript
const AuditableActions = [
  // Authentication
  'auth.login', 'auth.logout', 'auth.failed', 'auth.mfa_enabled',

  // Authorization changes
  'graph.share_created', 'graph.share_revoked',
  'graph.collaborator_added', 'graph.collaborator_removed',

  // Data lifecycle
  'graph.deleted', 'node.deleted', 'account.deleted',

  // API key management
  'apikey.created', 'apikey.rotated', 'apikey.deleted',

  // Admin actions
  'admin.user_suspended', 'admin.graph_flagged',
] as const;

interface AuditLogEntry {
  action: typeof AuditableActions[number];
  userId: string | null;  // null for unauthenticated actions
  resourceType: 'graph' | 'node' | 'user' | 'apikey';
  resourceId: string;
  details: Record<string, unknown>;
  ipAddress: string;
  userAgent: string;
  timestamp: string;
}
```

---

## 11. Performance Considerations

### 11.1 Two-Phase Graph Loading

Large graphs require a two-phase loading strategy to meet performance targets:

```
Phase 1: Structure Load (Target: <300ms)
├── Graph metadata (title, settings, stats)
├── Node IDs and parent relationships
├── Node metadata (model, status, timestamps)
├── Prompt previews (first 100 chars)
└── Edge list

Phase 2: Content Load (On-demand, per node)
├── Full user prompt
├── Full AI response (textMarkdown)
├── Usage statistics
└── Annotations
```

**Implementation**:
```typescript
// Phase 1: Fast structure load
GET /api/graphs/:graphId
Response size: ~50KB for 500 nodes

// Phase 2: Individual node content (lazy)
GET /api/graphs/:graphId/nodes/:nodeId
Response size: ~5-50KB per node

// Phase 2 optimization: Batch load visible nodes
POST /api/graphs/:graphId/nodes/batch-read
Body: { nodeIds: ["id1", "id2", ...] }
```

### 11.2 Optimization Strategies

**Frontend**:
- Virtual scrolling for long conversations
- Canvas rendering optimizations (only visible nodes via React Flow's built-in virtualization)
- Lazy loading of node content (fetch on selection or viewport entry)
- Debounced auto-save (500ms after last change)
- Optimistic UI updates (show immediately, reconcile on server response)
- Service Worker caching for offline graph structure access

**Backend**:
- Redis caching:
  - Graph structure: 10-minute TTL, invalidate on mutation
  - User session: 1-hour TTL
  - Rate limit counters: sliding window
- Connection pooling:
  - PostgreSQL: 20 connections per instance
  - Redis: 10 connections per instance
  - AI providers: HTTP/2 connection reuse
- Response streaming via Server-Sent Events (SSE) for AI responses
- Background job processing via BullMQ for non-blocking AI requests

**Database** (see Section 4.3 for full index definitions):
- Composite indexes for common query patterns
- Partial indexes for active/pending queries
- GIN indexes for JSONB and full-text search
- Read replicas (optional) for read-heavy workloads
- Connection pooling via PgBouncer in production

### 11.3 Scalability Targets

| Metric | Target | Notes |
|--------|--------|-------|
| Concurrent Users | 10,000+ | Per region/cluster |
| Graphs per User | Unlimited | Storage quota enforcement |
| Nodes per Graph | 2,000 hard limit | Warn at 1,000 nodes |
| Max Children per Node | 50 | Prevent runaway branching |
| Max Graph Depth | 100 levels | Prevent infinite recursion |

**Response Time Targets**:
| Operation | Target (p95) | Notes |
|-----------|--------------|-------|
| Graph structure load (<200 nodes) | <300ms | Phase 1 only |
| Graph structure load (500 nodes) | <500ms | Phase 1 only |
| Graph structure load (2000 nodes) | <1.5s | Phase 1 only |
| Full graph load (<50 nodes) | <500ms | Both phases |
| Single node content load | <100ms | Phase 2 |
| Node creation (DB only) | <200ms | Excluding AI |
| AI response first token | <2s | Provider-dependent |
| Search (within graph) | <500ms | Full-text search |
| Search (across graphs) | <2s | Paginated results |

### 11.4 Load Testing Strategy

```yaml
# k6 load test configuration
scenarios:
  smoke:
    executor: 'constant-vus'
    vus: 10
    duration: '1m'

  load:
    executor: 'ramping-vus'
    startVUs: 0
    stages:
      - duration: '2m', target: 100
      - duration: '5m', target: 100
      - duration: '2m', target: 0

  stress:
    executor: 'ramping-vus'
    startVUs: 0
    stages:
      - duration: '2m', target: 200
      - duration: '5m', target: 500
      - duration: '2m', target: 1000
      - duration: '5m', target: 1000
      - duration: '5m', target: 0
```

### 11.5 Monitoring Thresholds

```typescript
const AlertThresholds = {
  // Latency
  graphLoadP95: 1000,      // ms
  nodeCreateP95: 500,      // ms
  aiFirstTokenP95: 5000,   // ms

  // Error rates
  errorRate5xx: 0.01,      // 1%
  errorRate4xx: 0.05,      // 5%

  // Queue health
  queueDepth: 1000,        // jobs
  queueLatencyP95: 30000,  // ms

  // Resources
  cpuUsage: 80,            // %
  memoryUsage: 85,         // %
  dbConnectionUsage: 80,   // %
};

---

## 12. Development Roadmap

### Phase 1: MVP (8-10 weeks)
**Weeks 1-2**: Architecture setup & core data models
**Weeks 3-4**: Graph manager & database integration
**Weeks 5-6**: Basic UI (canvas + conversation panel)
**Weeks 7-8**: AI model integration (OpenAI, Claude)
**Weeks 9-10**: Testing, bug fixes, deployment

### Phase 2: Enhancement (6-8 weeks)
**Weeks 11-12**: Advanced graph layouts & navigation
**Weeks 13-14**: Additional models (Gemini, custom)
**Weeks 15-16**: Export/import functionality
**Weeks 17-18**: Polish, performance optimization

### Phase 3: Advanced Features (Ongoing)
- Collaborative editing
- Mobile apps (React Native)
- AI-assisted graph analysis
- Template marketplace
- Enterprise features (SSO, audit logs)

---

## 13. Success Metrics

### 13.1 User Engagement
- **Daily Active Users (DAU)**: Target 1,000+ after 3 months
- **Conversations Created**: 10+ per user per week
- **Avg. Graph Depth**: 3-5 levels
- **Retention**: 40%+ 30-day retention

### 13.2 Technical Performance
- **Uptime**: 99.9%
- **API Response Time**: p95 < 500ms
- **Error Rate**: <0.1%
- **AI Response Success**: >99%

### 13.3 Business Metrics
- **Conversion Rate**: Free -> Paid (target 5%)
- **Churn**: <3% monthly
- **LTV:CAC**: >3:1

---

## 14. Risk Assessment & Mitigation

### 14.1 Technical Risks

**Risk**: AI API rate limits or downtime
**Mitigation**:
- Multi-provider fallback
- Request queuing with retry logic
- User notifications for service interruptions

**Risk**: Performance degradation with large graphs (rendering + traversal queries)
**Mitigation**:
- Implement pagination and lazy loading
- Set soft limits with user warnings
- Archival system for inactive graphs

### 14.2 Business Risks

**Risk**: High AI API costs eating into margins
**Mitigation**:
- Usage-based pricing tiers
- Cost monitoring dashboard for users
- Caching of identical requests (opt-in, per-user/per-graph only; never cross-user)
- Option for users to bring own API keys

**Risk**: Competitor with better UX or features
**Mitigation**:
- Rapid iteration based on user feedback
- Unique features (multi-model, graph view)
- Strong community engagement

### 14.3 User Experience Risks

**Risk**: Learning curve too steep for casual users
**Mitigation**:
- Interactive onboarding tutorial
- Template library with examples
- Video tutorials and documentation
- Progressive disclosure of advanced features

---

## 15. Testing Strategy

### 15.1 Unit Tests
- Graph manager operations (create, update, delete, traverse)
- Model router logic
- Data model validation

### 15.2 Integration Tests
- AI API interactions (mock responses)
- Database operations (PostgreSQL queries)
- WebSocket event flow

### 15.3 End-to-End Tests
- User flows: Create graph -> Branch conversation -> Navigate
- Multi-model switching
- Export functionality

### 15.4 Performance Tests
- Load testing: 1,000 concurrent users
- Large graph rendering (500+ nodes)
- AI response streaming latency

### 15.5 User Acceptance Testing
- Beta program with 50-100 early adopters
- Feedback surveys after each session
- A/B testing for UI variations

---

## 16. Observability & Operations

### 16.1 Logging

**Structured Logging with Pino**:
```typescript
import pino from 'pino';

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  formatters: {
    level: (label) => ({ level: label }),
  },
  redact: {
    paths: ['req.headers.authorization', 'apiKey', 'password'],
    censor: '[REDACTED]',
  },
});

// Request logging middleware
app.use((req, res, next) => {
  const requestId = req.headers['x-request-id'] || uuidv4();
  req.log = logger.child({
    requestId,
    userId: req.user?.id,
    method: req.method,
    path: req.path,
  });
  next();
});
```

**Log Levels by Environment**:
- Development: `debug`
- Staging: `info`
- Production: `warn` (with `info` available via config toggle)

### 16.2 Metrics (Prometheus)

**Key Metrics**:
```typescript
const metrics = {
  // HTTP
  httpRequestDuration: new Histogram({
    name: 'http_request_duration_seconds',
    help: 'HTTP request duration',
    labelNames: ['method', 'route', 'status'],
    buckets: [0.01, 0.05, 0.1, 0.5, 1, 2, 5],
  }),

  // AI Provider
  aiRequestDuration: new Histogram({
    name: 'ai_request_duration_seconds',
    help: 'AI provider request duration',
    labelNames: ['provider', 'model', 'status'],
    buckets: [0.5, 1, 2, 5, 10, 30, 60],
  }),
  aiTokensUsed: new Counter({
    name: 'ai_tokens_total',
    help: 'Total AI tokens used',
    labelNames: ['provider', 'model', 'type'], // type: input/output
  }),

  // Queue
  queueJobDuration: new Histogram({
    name: 'queue_job_duration_seconds',
    help: 'Queue job processing duration',
    labelNames: ['queue', 'status'],
  }),
  queueDepth: new Gauge({
    name: 'queue_depth',
    help: 'Current queue depth',
    labelNames: ['queue', 'status'], // status: waiting/active/delayed
  }),

  // Database
  dbQueryDuration: new Histogram({
    name: 'db_query_duration_seconds',
    help: 'Database query duration',
    labelNames: ['operation', 'table'],
  }),
  dbPoolConnections: new Gauge({
    name: 'db_pool_connections',
    help: 'Database connection pool status',
    labelNames: ['status'], // status: total/idle/waiting
  }),

  // WebSocket
  wsConnectionsActive: new Gauge({
    name: 'ws_connections_active',
    help: 'Active WebSocket connections',
  }),
  wsMessagesTotal: new Counter({
    name: 'ws_messages_total',
    help: 'WebSocket messages sent/received',
    labelNames: ['direction', 'event'],
  }),
};
```

### 16.3 Distributed Tracing (OpenTelemetry)

```typescript
import { NodeTracerProvider } from '@opentelemetry/sdk-trace-node';
import { Resource } from '@opentelemetry/resources';
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions';

const provider = new NodeTracerProvider({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: 'convograph-api',
    [SemanticResourceAttributes.SERVICE_VERSION]: process.env.VERSION,
    [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]: process.env.NODE_ENV,
  }),
});

// Trace context propagation
// - HTTP: W3C Trace Context headers
// - Queue jobs: traceId/spanId in job metadata
// - WebSocket: traceId in event payload
```

**Key Traces**:
- Request → Auth → GraphManager → Database → Response
- NodeCreate → Queue → Worker → AIProvider → WebSocket

### 16.4 Error Tracking (Sentry)

```typescript
import * as Sentry from '@sentry/node';

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV,
  tracesSampleRate: 0.1, // 10% of transactions
  beforeSend(event) {
    // Scrub sensitive data
    if (event.request?.headers) {
      delete event.request.headers['authorization'];
    }
    return event;
  },
});

// Error boundary for AI provider failures
try {
  await aiProvider.complete(request);
} catch (error) {
  Sentry.captureException(error, {
    tags: { provider: request.model.split(':')[0] },
    extra: { model: request.model, promptLength: request.prompt.length },
  });
  throw error;
}
```

### 16.5 Alerting Rules

```yaml
# Prometheus alerting rules
groups:
  - name: convograph
    rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.01
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High 5xx error rate ({{ $value | humanizePercentage }})"

      - alert: AIProviderDown
        expr: up{job="ai-provider-health"} == 0
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "AI provider {{ $labels.provider }} is unreachable"

      - alert: QueueBacklog
        expr: queue_depth{status="waiting"} > 1000
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Queue backlog exceeds 1000 jobs"

      - alert: DatabaseConnectionExhaustion
        expr: db_pool_connections{status="waiting"} > 5
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Database connection pool exhausted"
```

---

## 17. Offline Support & PWA

### 17.1 Service Worker Strategy

```typescript
// sw.js - Workbox configuration
import { precacheAndRoute } from 'workbox-precaching';
import { registerRoute } from 'workbox-routing';
import { StaleWhileRevalidate, NetworkFirst, CacheFirst } from 'workbox-strategies';

// Precache static assets
precacheAndRoute(self.__WB_MANIFEST);

// API: Network-first with fallback
registerRoute(
  ({ url }) => url.pathname.startsWith('/api/graphs'),
  new NetworkFirst({
    cacheName: 'api-graphs',
    networkTimeoutSeconds: 5,
    plugins: [
      new ExpirationPlugin({ maxEntries: 50, maxAgeSeconds: 60 * 10 }), // 10 min
    ],
  })
);

// Graph structure: Stale-while-revalidate
registerRoute(
  ({ url }) => url.pathname.match(/\/api\/graphs\/[^/]+$/),
  new StaleWhileRevalidate({
    cacheName: 'graph-structure',
    plugins: [
      new ExpirationPlugin({ maxEntries: 20, maxAgeSeconds: 60 * 60 }), // 1 hour
    ],
  })
);

// Static assets: Cache-first
registerRoute(
  ({ request }) => request.destination === 'image' || request.destination === 'font',
  new CacheFirst({
    cacheName: 'static-assets',
    plugins: [
      new ExpirationPlugin({ maxEntries: 100, maxAgeSeconds: 60 * 60 * 24 * 30 }), // 30 days
    ],
  })
);
```

### 17.2 Offline Capabilities (MVP)

| Feature | Offline Support | Sync Strategy |
|---------|-----------------|---------------|
| View cached graphs | ✅ Full | Read from cache |
| Navigate graph structure | ✅ Full | Read from cache |
| Read node content | ⚠️ Partial | Only previously loaded nodes |
| Create new nodes | ❌ None | Requires AI provider |
| Edit annotations | ⚠️ Queued | Sync when online |
| Search within graph | ⚠️ Partial | Cached content only |

### 17.3 Conflict Resolution

When edits are made offline and synced later:

```typescript
interface PendingEdit {
  id: string;
  nodeId: string;
  type: 'annotation_update';
  payload: Partial<ConversationNode['annotations']>;
  timestamp: string;
  baseVersion: number;
}

// On reconnect:
async function syncPendingEdits(edits: PendingEdit[]) {
  for (const edit of edits) {
    try {
      await api.updateNode(edit.nodeId, edit.payload, edit.baseVersion);
    } catch (error) {
      if (error.code === 'VERSION_CONFLICT') {
        // Fetch current state and prompt user to resolve
        const current = await api.getNode(edit.nodeId);
        await promptConflictResolution(edit, current);
      }
    }
  }
}
```

---

## 18. Accessibility

### 18.1 WCAG 2.1 AA Compliance

**Target**: WCAG 2.1 Level AA compliance

**Key Requirements**:
- **Perceivable**: All non-text content has text alternatives
- **Operable**: All functionality available via keyboard
- **Understandable**: Consistent navigation, input assistance
- **Robust**: Compatible with assistive technologies

### 18.2 Graph Navigation Accessibility

```typescript
// Keyboard navigation for graph canvas
const keyboardBindings = {
  // Node navigation
  'ArrowUp': 'Select parent node',
  'ArrowDown': 'Select first child node',
  'ArrowLeft': 'Select previous sibling',
  'ArrowRight': 'Select next sibling',
  'Enter': 'Open node in conversation panel',
  'Space': 'Toggle node expanded/collapsed',

  // Canvas navigation
  '+': 'Zoom in',
  '-': 'Zoom out',
  '0': 'Reset zoom',
  'Home': 'Focus root node',

  // Actions
  'n': 'Create new branch from selected node',
  'Delete': 'Delete selected node (with confirmation)',
  '/': 'Open search',
  '?': 'Show keyboard shortcuts',
};

// ARIA live regions for graph updates
<div role="status" aria-live="polite" aria-atomic="true">
  {statusMessage} {/* "Node created", "Navigated to node X", etc. */}
</div>
```

### 18.3 Screen Reader Support

```tsx
// Node component with ARIA
<div
  role="treeitem"
  aria-level={depth}
  aria-expanded={hasChildren ? isExpanded : undefined}
  aria-selected={isSelected}
  aria-label={`
    ${node.request.model} node.
    Prompt: ${truncate(node.request.userPrompt, 100)}.
    ${node.annotations.starred ? 'Starred.' : ''}
    ${hasChildren ? `${childCount} children.` : 'No children.'}
  `}
  tabIndex={isSelected ? 0 : -1}
>
  {/* Visual content */}
</div>

// Conversation panel
<main role="main" aria-label="Conversation panel">
  <nav aria-label="Breadcrumb navigation">
    <ol role="list">
      {ancestry.map((node, i) => (
        <li key={node.id}>
          <a href={`#node-${node.id}`} aria-current={i === ancestry.length - 1 ? 'page' : undefined}>
            {truncate(node.request.userPrompt, 30)}
          </a>
        </li>
      ))}
    </ol>
  </nav>
</main>
```

### 18.4 Color & Contrast

- Minimum contrast ratio: 4.5:1 for normal text, 3:1 for large text
- Model colors include patterns/icons, not just color differentiation
- High contrast mode toggle in settings
- Dark mode with appropriate contrast ratios

### 18.5 Focus Management

```typescript
// Focus trap in modal dialogs
import { FocusTrap } from '@headlessui/react';

// Focus restoration after actions
const previousFocus = useRef<HTMLElement>();
function openBranchDialog() {
  previousFocus.current = document.activeElement as HTMLElement;
  setDialogOpen(true);
}
function closeBranchDialog() {
  setDialogOpen(false);
  previousFocus.current?.focus();
}
```

---

## 19. Internationalization (i18n)

### 19.1 Strategy

**MVP**: English only, with i18n infrastructure in place
**Post-MVP**: Spanish, French, German, Japanese, Chinese (Simplified)

### 19.2 Implementation

```typescript
// Using react-i18next
import i18n from 'i18next';
import { initReactI18next } from 'react-i18next';

i18n.use(initReactI18next).init({
  lng: 'en',
  fallbackLng: 'en',
  interpolation: {
    escapeValue: false, // React already escapes
  },
  resources: {
    en: {
      translation: {
        'graph.create': 'New Conversation',
        'node.branch': 'Branch Conversation',
        'node.model.select': 'Select AI Model',
        'error.conflict': 'This item was modified. Please refresh and try again.',
        // ...
      },
    },
  },
});

// Usage
function BranchButton() {
  const { t } = useTranslation();
  return <button>{t('node.branch')}</button>;
}
```

### 19.3 Content Considerations

- **AI Responses**: Stored and displayed in original language (user's choice)
- **UI Strings**: Translated based on user locale preference
- **Timestamps**: Formatted per locale (`Intl.DateTimeFormat`)
- **Numbers**: Formatted per locale (`Intl.NumberFormat`)
- **RTL Support**: Infrastructure in place for Arabic/Hebrew (post-MVP)

### 19.4 Translation Workflow

```yaml
# locize or similar translation management
workflow:
  1. Developers add keys in code with English defaults
  2. Keys extracted to translation management platform
  3. Translators work in platform with context screenshots
  4. Translations pulled into codebase via CI/CD
  5. Missing translations fall back to English
```

---

## 20. Competitive Analysis

### 20.1 Existing Solutions

**ChatGPT (OpenAI)**:
- Pros: Strong model, fast responses
- Cons: Linear conversations only
- Cons: No branching or graph view

**Claude.ai (Anthropic)**:
- Pros: Good context handling
- Cons: Linear conversations
- Cons: Single model per conversation

**Poe (Quora)**:
- Pros: Multiple models in one platform
- Cons: Separate conversations per model
- Cons: No interconnection between chats

**Obsidian + AI Plugins**:
- Pros: Note linking and graph view
- Cons: Requires manual setup and prompt engineering
- Cons: Not purpose-built for AI conversations

### 20.2 Competitive Advantages

1. **Unique Graph-Based UX**: First tool to treat conversations as visual networks
2. **Model Agnostic**: Switch models mid-conversation seamlessly
3. **Context Preservation**: Highlighted text creates natural conversation branches
4. **Visual Thinking**: Appeals to visual learners and researchers
5. **Obsidian-Like Power**: Familiar to knowledge workers who use linked note systems

---

## 21. Monetization Strategy

### 21.1 Pricing Tiers

**Free Tier**:
- 5 graphs
- 50 nodes per graph
- Budget models only (tier-gated model catalog)
- 7-day retention

**Pro Tier** ($15/month):
- Unlimited graphs
- 2,000 nodes per graph (warn at 1,000)
- All enabled models (tier-gated model catalog)
- Unlimited history
- Export to PDF/Markdown
- Priority support

**Team Tier** ($10/user/month, min 5 users):
- All Pro features
- Collaborative graphs
- Shared workspace
- Admin dashboard
- SSO (Google Workspace, Okta)

**Enterprise** (Custom pricing):
- Self-hosted option
- Custom models (fine-tuned, private deployments)
- Audit logs
- Dedicated support
- SLA guarantees

### 21.2 Revenue Projections (Year 1)

- Month 3: 1,000 free users, 50 paid ($750 MRR)
- Month 6: 5,000 free users, 250 paid ($3,750 MRR)
- Month 12: 20,000 free users, 1,000 paid ($15,000 MRR)
- Year 1 Total: ~$90K ARR

---

## 22. Design Decisions & Clarifications

This section documents key design decisions and answers common questions about the architecture.

### 22.1 Conversation Model

**Q: Can users have multi-turn conversations within a single node?**
A: No. Each node represents exactly one exchange (user prompt → AI response). Multi-turn conversations are modeled as chains of nodes. This ensures every exchange is individually addressable for branching and maintains clear graph semantics.

**Q: What happens when a user wants to "continue" a conversation?**
A: Continuing creates a child node with the parent's context. The user types their follow-up, which becomes the child node's prompt. The full ancestry is included in the AI request context.

### 22.2 Regeneration Behavior

**Q: What happens to children when a node is regenerated?**
A: Children are preserved. They reference the node ID, not the response content. The regenerated response may diverge from the context children were created with, but this is intentional—users can create branches exploring alternate paths.

**Q: Is regeneration history preserved?**
A: Configurable per request. If `preserveHistory: true`, the old response moves to `response.previousVersions[]`. Default is `false` (overwrite) to save storage.

### 22.3 Node Deletion

**Q: What happens when a non-leaf node is deleted?**
A: Two options provided via API:
1. `cascade: true` (default): Delete node and all descendants
2. `cascade: false`: Promote children to be children of the deleted node's parent (re-parenting)

Re-parenting preserves child content but loses the intermediate context. Users are warned before deletion.

### 22.4 Model Context Inheritance

**Q: When branching to a model with smaller context window, how is ancestry truncated?**
A: The system implements smart truncation:
1. Always include: highlighted anchor text + new prompt
2. Include as much ancestry as fits, prioritizing:
   - Direct parent (most relevant)
   - Root node (original context)
   - Recent ancestors over distant ones
3. Use summarization (optional, post-MVP) for long ancestry chains
4. Display warning to user when truncation occurs

### 22.5 Template Ownership

**Q: Are templates per-user or shared?**
A: Three levels:
1. **Personal templates**: User-created, private
2. **Team templates**: Shared within workspace (Team tier)
3. **Community templates**: Publicly shared (moderated, post-MVP)

### 22.6 Rate Limiting Philosophy

**Q: Why limit node creation per graph?**
A: Prevents accidental runaway branching (e.g., a bug in client code creating infinite branches). The limit (20/minute) is high enough for normal use but catches automation errors.

### 22.7 Offline-First Decision

**Q: Why not support offline node creation?**
A: AI generation requires provider connectivity. We chose not to queue prompts offline because:
1. Users expect immediate feedback
2. Context may become stale
3. Cost implications of queued requests
4. Simpler mental model

Annotations and navigation work offline; creation requires connectivity.

### 22.8 Database Choice

**Q: Why PostgreSQL over a native graph database?**
A: For MVP, PostgreSQL with JSONB provides:
1. Simpler operations (single database)
2. Strong ACID guarantees
3. Excellent JSON querying
4. Mature ecosystem
5. Cost-effective

Neo4j is planned as optional read-optimized store post-MVP if graph traversal queries become bottlenecks at scale.

### 22.9 WebSocket vs SSE

**Q: Why use Socket.io instead of Server-Sent Events for streaming?**
A: Socket.io provides:
1. Bidirectional communication (needed for presence, collaboration)
2. Automatic reconnection with state recovery
3. Room-based subscription (per-graph)
4. Built-in Redis adapter for scaling

For MVP, the added complexity is justified by collaboration features roadmap.

### 22.10 API Key Security

**Q: Why store BYOK keys server-side instead of client-side?**
A: Server-side storage provides:
1. Keys never exposed to browser (no XSS risk)
2. Unified rate limiting across user's sessions
3. Audit trail of all usage
4. Easier key rotation
5. Works across devices

The tradeoff is trust in our encryption—mitigated by KMS and audit logging.

---

## 23. Conclusion

**ConvoGraph** solves a critical pain point in AI interaction: the inability to explore ideas non-linearly while maintaining context. By treating conversations as graph structures rather than linear threads, we enable:

- **Deeper exploration** through branching dialogues
- **Model flexibility** to leverage strengths of different AI systems
- **Visual comprehension** of complex reasoning chains
- **Efficient navigation** of multi-faceted discussions

The tool bridges the gap between traditional chat interfaces and knowledge management systems like Obsidian, creating a new category: **Conversation Knowledge Networks**.

### Next Steps

1. **Validation**: Build clickable prototype in Figma, test with 20 target users
2. **Technical Spike**: Validate PostgreSQL schema + React Flow with sample data (and decide if a derived Neo4j store is needed post-MVP)
3. **MVP Development**: 10-week sprint to launch with OpenAI and Claude support
4. **Beta Launch**: Invite early adopters, gather feedback, iterate rapidly

This represents a fundamental rethinking of how humans interact with AI for complex, multi-faceted problems. The market is ready for tools that match the non-linear nature of human thought.

---

## Appendix A: Technology Stack Details

### Frontend Dependencies (Indicative)
- `react`, `typescript`
- React Flow (graph rendering/interactions)
- `zustand` (or Redux Toolkit)
- `tailwindcss`
- `@tiptap/react` (or Lexical) for selection/annotations
- `socket.io-client` (streaming/collaboration)
- `axios` (optional; `fetch` is fine)

### Backend Dependencies (Indicative)
- `fastify` (or `express`)
- `typescript`
- `pg` (PostgreSQL) + migrations/ORM of choice
- `redis`
- `socket.io`
- `jsonwebtoken`
- Provider adapters: `openai`, `@anthropic-ai/sdk`, and the relevant Google SDK
- Optional (post-MVP): `neo4j-driver` for a derived analytics store

---

## Appendix B: Example Use Cases

### Use Case 1: Research Paper Analysis
1. User uploads paper abstract
2. Asks GPT-4: "Summarize the key findings"
3. Highlights "neural network architecture" in response
4. Branches to Claude: "Explain this architecture in detail"
5. Highlights "transformer attention mechanism"
6. Branches to Gemini: "Compare this to traditional RNNs"
Result: Visual map of research exploration paths

### Use Case 2: Code Review
1. Pastes code snippet to GPT-4
2. Highlights security concern in response
3. Branches to Claude for security audit
4. Highlights performance suggestion
5. Branches back to GPT-4 for optimization strategies
Result: Multi-perspective code analysis

### Use Case 3: Creative Writing
1. Asks Claude for story premise
2. Highlights character description
3. Branches to GPT-4: "Write backstory for this character"
4. Highlights plot twist idea
5. Branches to different model for alternate development
Result: Parallel narrative explorations

---

**Document Version**: 2.0
**Last Updated**: 2026-02-03
**Author**: ConvoGraph Design Team
**Status**: Technical Review Complete - Ready for Implementation Planning

**Revision History**:
| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-03 | Initial draft |
| 2.0 | 2026-02-03 | Technical review incorporated: Added message queue architecture, caching strategy, optimistic locking, input validation, CSP/XSS protection, two-phase loading, observability stack, offline support, accessibility, i18n, and design clarifications |
