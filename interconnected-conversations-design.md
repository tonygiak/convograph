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
+--------------------------------------------------+
| Presentation Layer (Frontend)                    |
|  - Canvas renderer (graph view)                  |
|  - Conversation panel (active node)              |
+--------------------------------------------------+
                       |
+--------------------------------------------------+
| Application Layer (Business Logic)               |
|  - Graph manager (nodes/edges, traversal)        |
|  - Model router & orchestrator                   |
+--------------------------------------------------+
                       |
+--------------------------------------------------+
| Integration Layer (AI Models)                    |
|  - OpenAI / Anthropic / Google / Custom          |
+--------------------------------------------------+
                       |
+--------------------------------------------------+
| Data Layer (Persistence)                         |
|  - Graph + content store                         |
|  - Cache (optional)                              |
+--------------------------------------------------+
```

### 3.2 Core Components

#### 3.2.1 Graph Manager
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

#### 3.2.2 Model Router & Orchestrator
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

#### 3.2.3 Canvas Renderer
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

#### 3.2.4 Conversation Panel
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

**Selection anchoring**:
- A branch is created from a **text anchor** inside the parent node's AI response.
- Offsets, when present, are defined against the exact stored source string (`response.textMarkdown`) using UTF-16 code unit offsets (browser-native indexing).
- To tolerate minor formatting edits, store a quote-style selector (`prefix`/`exact`/`suffix`) in addition to offsets.

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
    finishReason?: string
  }

  spawnedFrom?: {
    sourceNodeId: string
    anchor: TextAnchor
  }

  usage?: {
    inputTokens?: number
    outputTokens?: number
    costUsd?: number
  }

  annotations: {
    tags: string[]
    notes?: string
    starred: boolean
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

  // API-friendly shape (JSON-serializable)
  nodesById: Record<string, ConversationNode>
  edges: GraphEdge[]

  createdAt: string // ISO timestamp
  updatedAt: string // ISO timestamp

  totals?: {
    totalTokens?: number
    totalCostUsd?: number
  }

  tags: string[]
  folderId?: string

  sharing: {
    visibility: 'private' | 'link-view' | 'invite-only'
    shareId?: string // random, unguessable token used for link sharing
  }

  collaborators?: Array<{
    userId: string
    role: 'owner' | 'editor' | 'viewer'
  }>
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

**Notes**:
- Large text fields (`response.textMarkdown`) live in `nodes` (or in object storage if needed later), not duplicated in multiple databases.
- Tree invariants are enforced with constraints (e.g., exactly one `spawned_from` incoming edge per non-root node).

#### Optional Read-Optimized Graph Store (Neo4j) - Post-MVP

If traversal/query needs outgrow PostgreSQL, maintain a **derived** Neo4j representation for fast graph analytics. In that case:
- PostgreSQL remains the source of truth.
- Neo4j is updated asynchronously from the edge stream (event-driven), with backfill tooling.
This avoids inconsistency bugs caused by synchronous dual writes.

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
GET    /api/graphs/:graphId                 # Get graph (nodes + edges)
PUT    /api/graphs/:graphId                 # Update graph metadata (title/tags/folder)
DELETE /api/graphs/:graphId                 # Soft delete graph

GET    /api/graphs/:graphId/export?format=json|md|pdf
POST   /api/graphs/:graphId/share           # Create/revoke share link
GET    /api/shares/:shareId                 # Read-only access via share token (when enabled)
```

#### Node Operations
```
POST   /api/graphs/:graphId/nodes                 # Create node (root if parentId is null/omitted)
GET    /api/graphs/:graphId/nodes/:nodeId         # Get node details
PUT    /api/graphs/:graphId/nodes/:nodeId         # Update node (annotations, etc.)
DELETE /api/graphs/:graphId/nodes/:nodeId         # Delete node

POST   /api/graphs/:graphId/nodes/:nodeId/regenerate
GET    /api/graphs/:graphId/nodes/:nodeId/children
GET    /api/graphs/:graphId/nodes/:nodeId/ancestry
```

**Create Node Request (example)**
```
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
  "stream": true,
  "clientRequestId": "uuid-for-idempotency"
}
```

### 9.2 WebSocket Events

```typescript
// Client -> Server
socket.emit('node:create', { graphId, parentId, prompt, model, anchor, clientRequestId })
socket.emit('node:update', { nodeId, updates })
socket.emit('graph:subscribe', { graphId })

// Server -> Client
socket.on('node:created', { node })
socket.on('node:updated', { nodeId, updates })
socket.on('ai:response:chunk', { nodeId, chunk })
socket.on('ai:response:complete', { nodeId, fullResponse })
socket.on('user:joined', { userId, userName }) // Collaboration
```

---

## 10. Security & Privacy

### 10.1 Authentication
- **Methods**: OAuth 2.0 (Google, GitHub) and Email/Password (with email verification)
- **Password Storage**: Argon2id (or bcrypt with strong work factor) + per-user salt
- **Session Model**:
  - Short-lived access token (JWT, ~15 min)
  - Rotating refresh token (HTTP-only cookie, ~30 days) with server-side revocation
- **Account Linking**: Users can link OAuth identities to an existing email account (explicit consent flow)

### 10.2 Authorization
- **Roles**: `owner`, `editor`, `viewer`
- **Graph Ownership**: Creator is `owner` by default and can manage collaborators/shares
- **Share Links** (optional):
  - Link access uses an unguessable `shareId` token
  - Default is read-only (`link-view`) and can be revoked at any time
- **Permission Checks**: Every graph/node API call is authorized by `(userId, graphId, role)`; never by client-supplied `userId`

### 10.3 Data Privacy
- **API Keys**: Encrypted at rest (AES-256) with per-environment KMS-managed master key; decrypted only in memory for outbound requests
- **Bring Your Own Key (BYOK)**:
  - Stored server-side (encrypted) and scoped per user/workspace
  - Never returned in plaintext after initial entry
  - Used only for that user's requests (no cross-user caching/sharing)
- **Data Retention (Hosted SaaS)**:
  - Free tier: 7-day retention (active + deleted)
  - Paid tiers: Indefinite until deleted
  - Paid tiers deletion: 30-day soft delete, then permanent removal

### 10.4 Rate Limiting
- **Per User**: Tier-based (token bucket), with tighter limits on expensive models
- **Per Graph**: Node creation burst limits to prevent accidental runaway branching
- **Per Provider/Key**: Enforce provider quotas and backoff; surface clear UI errors when limits are hit

---

## 11. Performance Considerations

### 11.1 Optimization Strategies

**Frontend**:
- Virtual scrolling for long conversations
- Canvas rendering optimizations (only visible nodes)
- Lazy loading of node content
- Debounced auto-save

**Backend**:
- Redis caching for frequently accessed graphs
- Database indexing on graphId, userId, timestamps
- Connection pooling for AI API clients
- Response streaming for real-time feedback

**Database**:
- PostgreSQL indexing on `graphId`, `createdAt`, and common filters
- Pagination/lazy-loading for large graphs (structure first, content on demand)
- Read replicas (optional) for read-heavy workloads

### 11.2 Scalability Targets

- **Concurrent Users**: 10,000+
- **Graphs per User**: Unlimited (with storage quotas)
- **Nodes per Graph**: 2,000 (hard limit in hosted tiers; warn at 1,000)
- **Response Time**:
  - Graph load (<200 nodes): <500ms
  - Graph load (1,000+ nodes): <2s with pagination/lazy loading
  - Node creation (excluding AI): <200ms
  - AI response start: <2s (streaming)

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

## 16. Competitive Analysis

### 16.1 Existing Solutions

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

### 16.2 Competitive Advantages

1. **Unique Graph-Based UX**: First tool to treat conversations as visual networks
2. **Model Agnostic**: Switch models mid-conversation seamlessly
3. **Context Preservation**: Highlighted text creates natural conversation branches
4. **Visual Thinking**: Appeals to visual learners and researchers
5. **Obsidian-Like Power**: Familiar to knowledge workers who use linked note systems

---

## 17. Monetization Strategy

### 17.1 Pricing Tiers

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

### 17.2 Revenue Projections (Year 1)

- Month 3: 1,000 free users, 50 paid ($750 MRR)
- Month 6: 5,000 free users, 250 paid ($3,750 MRR)
- Month 12: 20,000 free users, 1,000 paid ($15,000 MRR)
- Year 1 Total: ~$90K ARR

---

## 18. Conclusion

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

**Document Version**: 1.0
**Last Updated**: 2026-02-03
**Author**: ConvoGraph Design Team
**Status**: Draft - Pending Technical Review
