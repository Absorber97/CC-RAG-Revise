# Import necessary libraries
import os
import tempfile
import streamlit as st
from dotenv import load_dotenv
from langchain_openai import ChatOpenAI, OpenAIEmbeddings
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import StrOutputParser
from langchain_core.runnables import RunnablePassthrough
from langchain_community.document_loaders import (
    PyPDFLoader,
    WebBaseLoader,
    WikipediaLoader,
    TextLoader,
)
from langchain_text_splitters import RecursiveCharacterTextSplitter
import socket
import logging
import weaviate
from weaviate.classes.init import Auth
from langchain_weaviate import WeaviateVectorStore
from pydantic import SecretStr

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load environment variables
_ = load_dotenv()

# API Keys
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY")
WEAVIATE_URL = os.environ.get("WEAVIATE_URL")
WEAVIATE_API_KEY = os.environ.get("WEAVIATE_API_KEY")

# Vector DB settings
WEAVIATE_CLASS_NAME = "SFBUDocuments"

logger.info("Using OpenAI for embeddings and Weaviate for vector storage")

# Initialize Streamlit app state
if "has_documents" not in st.session_state:
    st.session_state.has_documents = False


# Determine if this pod should be the writer pod
def is_writer_pod():
    # Check if there's a podinfo role file
    role_file = "/etc/podinfo/role"
    if os.path.exists(role_file):
        with open(role_file, "r") as f:
            role = f.read().strip()
            return role == "writer"

    # Fallback logic for local development
    hostname = socket.gethostname()
    replica_role = os.environ.get("REPLICA_ROLE", "")

    # If explicitly set as writer, use that
    if replica_role.lower() == "writer":
        return True

    # If explicitly set as reader, use that
    if replica_role.lower() == "reader":
        return False

    # Otherwise, use a deterministic approach based on hostname
    # This ensures at least one pod becomes a writer, even if it's not ideal for load distribution
    pod_number = -1
    
    # Try to extract pod number from hostname (e.g., streamlit-app-64b4448d6c-dccmp -> "dccmp")
    if "-" in hostname:
        pod_suffix = hostname.split("-")[-1]
        
        # If a StatefulSet is used, the hostname may end with an ordinal
        if pod_suffix.isdigit():
            pod_number = int(pod_suffix)
            
    # If we couldn't extract a number or it's not a StatefulSet, use first hostname alphabetically
    if pod_number == -1:
        return hostname == sorted([hostname])[0]
    else:
        # The first pod (index 0) becomes the writer
        return pod_number == 0


# Initialize OpenAI client
def init_openai():
    try:
        if not OPENAI_API_KEY:
            logger.error("No OpenAI API key found.")
            st.error("OpenAI API key is required. Please set OPENAI_API_KEY in your .env file.")
            st.stop()
            
        client = ChatOpenAI(api_key=OPENAI_API_KEY)
        logger.info("OpenAI client initialized successfully")
        return client
    except Exception as e:
        logger.error(f"Error initializing OpenAI: {str(e)}")
        return None


# Initialize OpenAI Embeddings
def init_openai_embeddings():
    try:
        if not OPENAI_API_KEY:
            logger.error("No OpenAI API key found.")
            st.error("OpenAI API key is required. Please set OPENAI_API_KEY in your .env file.")
            st.stop()
            
        embeddings = OpenAIEmbeddings(api_key=OPENAI_API_KEY)
        logger.info("OpenAI embeddings initialized successfully")
        return embeddings
    except Exception as e:
        logger.error(f"Error initializing OpenAI embeddings: {str(e)}")
        return None


# Initialize Weaviate client
def init_weaviate_client():
    try:
        if not WEAVIATE_URL:
            logger.error("No Weaviate URL found.")
            st.error("Weaviate URL is required. Please set WEAVIATE_URL in your .env file.")
            st.stop()
            
        if not WEAVIATE_API_KEY:
            logger.error("No Weaviate API key found.")
            st.error("Weaviate API key is required. Please set WEAVIATE_API_KEY in your .env file.")
            st.stop()
            
        # Make sure we have a valid OpenAI API key before using it
        api_key = OPENAI_API_KEY
        if not api_key:
            logger.error("No OpenAI API key found for Weaviate vectorizer.")
            st.error("OpenAI API key is required for Weaviate vectorizer.")
            st.stop()
        
        # Use the new Weaviate client API (v4)
        client = weaviate.connect_to_weaviate_cloud(
            cluster_url=WEAVIATE_URL,
            auth_credentials=Auth.api_key(WEAVIATE_API_KEY),
            headers={
                "X-OpenAI-Api-Key": api_key
            },
            skip_init_checks=True  # Skip gRPC health checks that might fail in some environments
        )
        logger.info("Weaviate client initialized successfully")
        return client
    except Exception as e:
        logger.error(f"Error initializing Weaviate client: {str(e)}")
        return None


# Initialize Vector Store
def init_vector_store(embedding_function, weaviate_client):
    try:
        # Check if the schema already exists, if not create it
        collection_name = WEAVIATE_CLASS_NAME
        
        # Check if collection exists by attempting to get it
        collection_exists = False
        try:
            weaviate_client.collections.get(collection_name)
            collection_exists = True
            logger.info(f"Collection {collection_name} already exists")
        except Exception as e:
            logger.info(f"Collection {collection_name} does not exist, will create it")
            collection_exists = False
        
        # Create collection if it doesn't exist
        if not collection_exists:
            # Define the collection properties
            try:
                weaviate_client.collections.create(
                    name=collection_name,
                    vectorizer_config=weaviate.classes.config.Configure.Vectorizer.text2vec_openai(
                        model="text-embedding-3-small",
                        model_version="latest"
                    ),
                    properties=[
                        weaviate.classes.config.Property(name="content", data_type=weaviate.classes.config.DataType.TEXT),
                        weaviate.classes.config.Property(name="source", data_type=weaviate.classes.config.DataType.TEXT),
                        # Define nested properties for metadata as required by Weaviate
                        weaviate.classes.config.Property(
                            name="metadata", 
                            data_type=weaviate.classes.config.DataType.OBJECT,
                            nested_properties=[
                                weaviate.classes.config.Property(name="page", data_type=weaviate.classes.config.DataType.NUMBER),
                                weaviate.classes.config.Property(name="url", data_type=weaviate.classes.config.DataType.TEXT),
                                weaviate.classes.config.Property(name="date", data_type=weaviate.classes.config.DataType.DATE)
                            ]
                        )
                    ]
                )
                logger.info(f"Created Weaviate collection for class {collection_name}")
            except Exception as e:
                logger.error(f"Error creating collection: {str(e)}")
                # Try to get the collection again in case it was created
                try:
                    weaviate_client.collections.get(collection_name)
                    logger.info(f"Collection {collection_name} exists despite creation error")
                    collection_exists = True
                except:
                    raise
        
        # Initialize Weaviate vector store with LangChain using the updated class
        vector_store = WeaviateVectorStore(
            client=weaviate_client,
            index_name=collection_name,
            text_key="content",
            embedding=embedding_function
        )
        
        # Check if it has documents
        try:
            collection = weaviate_client.collections.get(collection_name)
            # Fix for v4 API - proper way to get collection count
            count = collection.count()
            
            if count > 0:
                logger.info(f"Found {count} documents in vector store")
                st.session_state.has_documents = True
        except Exception as e:
            logger.warning(f"Couldn't get document count: {str(e)}")
        
        return vector_store
    except Exception as e:
        logger.error(f"Error initializing vector store: {str(e)}")
        raise


# Initialize clients and vector store
llm = init_openai()
embeddings = init_openai_embeddings()
weaviate_client = init_weaviate_client()

# Only proceed if clients are properly initialized
if llm and embeddings and weaviate_client:
    try:
        vector_store = init_vector_store(embeddings, weaviate_client)
        # Configure retriever for Weaviate - remove unsupported parameters
        retriever = vector_store.as_retriever(
            search_kwargs={
                "k": 4,             # Retrieve more documents for better context
                "alpha": 0.75,      # Balance between vector (higher) and keyword search
            }
        )
        string_parser = StrOutputParser()
    except Exception as e:
        st.error(f"Failed to initialize vector store: {str(e)}")
        vector_store = None
        retriever = None
else:
    vector_store = None
    retriever = None
    st.error("Initialization failed. Please check your API keys and Weaviate URL.")

# Define splitters and loaders
splitter = RecursiveCharacterTextSplitter(
    separators=["\n\n", "\n", " ", ""],
    chunk_size=1000,
    chunk_overlap=200,
    length_function=len,
    is_separator_regex=False,
)


def load_documents(file_path, loader_type="pdf"):
    if loader_type == "pdf":
        loader = PyPDFLoader(file_path)
    elif loader_type == "text":
        loader = TextLoader(file_path, encoding="utf-8")
    elif loader_type == "web":
        loader = WebBaseLoader(file_path)
    elif loader_type == "wiki":
        loader = WikipediaLoader(query=file_path, load_max_docs=2)
    else:
        raise ValueError("Unsupported loader type.")

    loaded_docs = loader.load()
    return splitter.split_documents(loaded_docs)


def embed_documents(docs):
    if not vector_store:
        st.error("Vector store not initialized. Please check your API keys and Weaviate URL.")
        return False
        
    # Check if this pod should handle writes
    if not is_writer_pod():
        st.warning(
            "Document uploads can only be processed by the writer pod. Your request will be redirected."
        )
        return False

    try:
        # Add documents to vector store
        vector_store.add_documents(docs)
        st.session_state.has_documents = True
        st.success("Documents embedded successfully!")
        return True
    except Exception as e:
        st.error(f"Error embedding documents: {str(e)}")
        return False


def rag_chatbot_app(question):
    if not retriever:
        return "Error: Vector store not initialized. Please check your API keys and Weaviate URL."

    if not st.session_state.has_documents:
        return (
            "No documents found in the knowledge base. Please upload documents first."
        )

    # Improved system prompt for better context processing
    system_prompt = """You are a helpful AI assistant for SFBU (South Bay for Business University).
Answer user questions based ONLY on the following context information. 
If the context doesn't contain relevant information to answer the question, just say 
"I don't have enough information to answer that question based on the available context."
Don't make up or infer information that's not in the context.

Context: {context}
"""
    main_prompt = ChatPromptTemplate.from_messages(
        [("system", system_prompt), ("user", "{question}")]
    )

    try:
        # Skip the chain if LLM is not initialized properly
        if not llm:
            return "Error: LLM not initialized properly."
            
        retrieval_chain = {"context": retriever, "question": RunnablePassthrough()}
        main_chain = (
            retrieval_chain 
            | main_prompt 
            | llm 
            | string_parser
        )
        return main_chain.invoke(question)
    except Exception as e:
        logger.error(f"Error in RAG chain: {str(e)}")
        return f"An error occurred: {str(e)}"


# Streamlit UI Setup
st.title("SFBU RAG Chatbot with Weaviate Cloud")

# Pod role indicator
if is_writer_pod():
    st.sidebar.success("💾 This pod can process document uploads")
else:
    st.sidebar.info("📖 This pod is read-only for documents")

# Status indicator
if st.session_state.has_documents:
    st.success("📚 Knowledge base is ready with documents")
else:
    st.warning("⚠️ No documents in knowledge base. Please upload some documents first.")

# Upload Documents section at the top
st.markdown("### Upload Documents")

# Only show the upload interface if this is a writer pod
if is_writer_pod():
    # Document type selector
    doc_type = st.selectbox("Select Document Type", ["PDF", "Text", "Web", "Wikipedia"])

    # Show appropriate input fields based on document type
    if doc_type == "PDF":
        uploaded_file = st.file_uploader("Upload a PDF file", type="pdf")
        if uploaded_file is not None:
            # Create a temporary file to process the PDF
            with tempfile.NamedTemporaryFile(delete=False, suffix=".pdf") as tmp_file:
                tmp_file.write(uploaded_file.getbuffer())
                temp_path = tmp_file.name

            if st.button("Process PDF"):
                with st.spinner("Processing PDF..."):
                    try:
                        docs = load_documents(temp_path, loader_type="pdf")
                        embed_documents(docs)
                        st.success(f"Processed {uploaded_file.name} successfully!")
                    except Exception as e:
                        st.error(f"Error processing PDF: {str(e)}")
                    finally:
                        # Clean up the temporary file
                        if os.path.exists(temp_path):
                            os.unlink(temp_path)

    elif doc_type == "Text":
        uploaded_file = st.file_uploader("Upload a Text file", type="txt")
        if uploaded_file is not None:
            # Create a temporary file to process the text file
            with tempfile.NamedTemporaryFile(delete=False, suffix=".txt") as tmp_file:
                tmp_file.write(uploaded_file.getbuffer())
                temp_path = tmp_file.name

            if st.button("Process Text File"):
                with st.spinner("Processing text file..."):
                    try:
                        docs = load_documents(temp_path, loader_type="text")
                        embed_documents(docs)
                        st.success(f"Processed {uploaded_file.name} successfully!")
                    except Exception as e:
                        st.error(f"Error processing text file: {str(e)}")
                    finally:
                        # Clean up the temporary file
                        if os.path.exists(temp_path):
                            os.unlink(temp_path)

    elif doc_type == "Web":
        url = st.text_input("Enter a webpage URL:")
        if url and st.button("Process Webpage"):
            with st.spinner("Processing webpage..."):
                try:
                    docs = load_documents(url, loader_type="web")
                    if embed_documents(docs):
                        st.success(f"Processed webpage {url} successfully!")
                except Exception as e:
                    st.error(f"Error processing webpage: {str(e)}")

    elif doc_type == "Wikipedia":
        query = st.text_input("Enter Wikipedia search query:")
        if query and st.button("Process Wikipedia Article"):
            with st.spinner("Processing Wikipedia article..."):
                try:
                    docs = load_documents(query, loader_type="wiki")
                    if embed_documents(docs):
                        st.success(
                            f"Processed Wikipedia article on '{query}' successfully!"
                        )
                except Exception as e:
                    st.error(f"Error processing Wikipedia article: {str(e)}")

else:
    st.info(
        "Document uploads are handled by the writer pod only. This pod is in read-only mode."
    )

# Chat interface below the document upload section
st.markdown("---")
st.markdown("### Chat with your documents")

if "openai_model" not in st.session_state:
    st.session_state["openai_model"] = "gpt-3.5-turbo"

if "messages" not in st.session_state:
    st.session_state.messages = []

# Display chat history
for message in st.session_state.messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])

# User input
if prompt := st.chat_input("Ask me anything based on the documents..."):
    # Append user's message
    st.session_state.messages.append({"role": "user", "content": prompt})
    with st.chat_message("user"):
        st.markdown(prompt)

    # Get assistant's response
    with st.chat_message("assistant"):
        # Generate response from the RAG chatbot
        with st.spinner("Thinking..."):
            try:
                response = rag_chatbot_app(prompt)
                st.markdown(response)
                # Append assistant's response
                st.session_state.messages.append(
                    {"role": "assistant", "content": response}
                )
            except Exception as e:
                error_message = f"Error generating response: {str(e)}"
                st.error(error_message)
                # Append error message to chat history
                st.session_state.messages.append(
                    {"role": "assistant", "content": error_message}
                )

# Add cleanup function for proper client termination
def cleanup():
    if 'weaviate_client' in globals() and weaviate_client is not None:
        try:
            weaviate_client.close()
            logger.info("Weaviate client closed properly")
        except Exception as e:
            logger.error(f"Error closing Weaviate client: {str(e)}")

# Register cleanup function with Streamlit, if running in Streamlit mode
try:
    import atexit
    atexit.register(cleanup)
except Exception:
    logger.warning("Could not register cleanup handler")


# Add a debug block at the end of the file
if __name__ == "__main__":
    import os
    print(f"DEBUG: OPENAI_API_KEY exists: {os.environ.get('OPENAI_API_KEY') is not None}")
    print(f"DEBUG: WEAVIATE_URL exists: {os.environ.get('WEAVIATE_URL') is not None}")
    print(f"DEBUG: WEAVIATE_API_KEY exists: {os.environ.get('WEAVIATE_API_KEY') is not None}")


# Add a debug block at the end of the file
if __name__ == "__main__":
    import os
    print(f"DEBUG: OPENAI_API_KEY exists: {os.environ.get('OPENAI_API_KEY') is not None}")
    print(f"DEBUG: WEAVIATE_URL exists: {os.environ.get('WEAVIATE_URL') is not None}")
    print(f"DEBUG: WEAVIATE_API_KEY exists: {os.environ.get('WEAVIATE_API_KEY') is not None}")
