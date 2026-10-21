import Foundation

enum MarkdownMermaidFixtures
{
	static let diagrams = [
		#"""
		flowchart TD
		    A[Start] --> B{Does the renderer support Mermaid?}
		    B -->|Yes| C[Render a diagram]
		    B -->|No| D[Show a code block]
		    C --> E[Finish]
		    D --> E
		"""#,
		#"""
		sequenceDiagram
		    participant User
		    participant Renderer
		    User->>Renderer: Markdown source
		    Renderer-->>User: Rendered output
		"""#,
		#"""
		flowchart TD
		    A([Start]) --> B[Parse Markdown]
		    B --> C{Mermaid supported?}
		    C -->|Yes| D[Render diagram]
		    C -->|No| E[Display source code]
		    D --> F([Finish])
		    E --> F
		"""#,
		#"""
		flowchart LR
		    subgraph Client
		        U[User] --> UI[Chat interface]
		    end

		    subgraph Backend
		        API[API] --> DB[(Database)]
		    end

		    UI --> API
		    API -. Response .-> UI

		    classDef highlighted fill:#dbeafe,stroke:#2563eb,color:#111827
		    class UI highlighted
		"""#,
		#"""
		sequenceDiagram
		    actor User
		    participant Chat
		    participant Renderer

		    User->>Chat: Paste Markdown
		    Chat->>Renderer: Render content
		    activate Renderer

		    alt Mermaid supported
		        Renderer-->>Chat: Diagram
		    else Mermaid unsupported
		        Renderer-->>Chat: Code block
		    end

		    deactivate Renderer
		    Chat-->>User: Display result
		    Note over User,Chat: Compare the rendered output
		"""#,
		#"""
		classDiagram
		    class Document {
		        +String title
		        +render()
		    }

		    class Block {
		        +String content
		        +parse()
		    }

		    class CodeBlock {
		        +String language
		        +highlight()
		    }

		    Document "1" *-- "0..*" Block : contains
		    Block <|-- CodeBlock
		"""#,
		#"""
		stateDiagram-v2
		    [*] --> Idle
		    Idle --> Parsing: Receive Markdown
		    Parsing --> Rendering: Valid input
		    Parsing --> Failed: Invalid input
		    Rendering --> Complete: Success
		    Rendering --> Failed: Render error
		    Failed --> Parsing: Retry
		    Complete --> [*]
		"""#,
		#"""
		erDiagram
		    USER ||--o{ CHAT : owns
		    CHAT ||--o{ MESSAGE : contains

		    USER {
		        string id PK
		        string name
		    }

		    CHAT {
		        string id PK
		        string user_id FK
		        string title
		    }

		    MESSAGE {
		        string id PK
		        string chat_id FK
		        string body
		    }
		"""#,
		#"""
		gantt
		    title Markdown Benchmark Schedule
		    dateFormat YYYY-MM-DD
		    axisFormat %b %d

		    section Preparation
		    Write examples    :done, source, 2026-10-01, 2d
		    Review syntax     :done, review, after source, 1d

		    section Validation
		    Test rendering    :active, render, after review, 3d
		    Compare results   :compare, after render, 2d
		    Benchmark ready   :milestone, ready, after compare, 0d
		"""#,
		#"""
		pie showData
		    title Example Benchmark Results
		    "Rendered correctly" : 70
		    "Partially supported" : 20
		    "Unsupported" : 10
		"""#,
		#"""
		mindmap
		    root((Markdown Benchmark))
		        Text
		            Headings
		            Emphasis
		            Links
		        Structure
		            Lists
		            Tables
		            Blockquotes
		        Extensions
		            Mathematics
		            Footnotes
		            Mermaid
		"""#
	]
	static let previewDocument = mathematics + "\n\n" + diagrams.map
	{
		"```mermaid\n" + $0 + "\n```"
	}.joined(separator: "\n\n")

	private static let mathematics = #"""
	## 18. Mathematics

	### Inline dollar delimiters

	The Pythagorean theorem is $a^2 + b^2 = c^2$.

	Euler's identity is $e^{i\pi} + 1 = 0$.

	### Display dollar delimiters

	$$
	\int_0^1 x^2\,dx = \frac{1}{3}
	$$

	### Aligned equations

	$$
	\begin{aligned}
	f(x) &= x^2 + 2x + 1 \\
	     &= (x + 1)^2
	\end{aligned}
	$$

	### Matrix

	$$
	A = \begin{bmatrix}
	1 & 2 \\
	3 & 4
	\end{bmatrix}
	$$

	### Piecewise expression

	$$
	|x| =
	\begin{cases}
	x, & x \ge 0 \\
	-x, & x < 0
	\end{cases}
	$$

	### Alternative LaTeX delimiters

	Inline: \( E = mc^2 \)

	Display:

	\[
	\sum_{k=1}^{n} k = \frac{n(n+1)}{2}
	\]
	"""#
}
