import React, { useState, useRef, useCallback, useEffect } from 'react';
import { Edit3, Pin, Move, Type } from 'lucide-react';

interface EditableFrameProps {
  children: React.ReactNode;
  onPositionChange?: (position: { x: number; y: number }) => void;
  onSizeChange?: (size: { width: number; height: number }) => void;
  onTextChange?: (text: string) => void;
  initialPosition?: { x: number; y: number };
  initialSize?: { width: number; height: number };
  initialText?: string;
  isPinned?: boolean;
  onPinChange?: (pinned: boolean) => void;
  storageKey?: string; // For localStorage persistence
  boundaryConstraints?: {
    leftMargin: number;
    rightMargin: number;
    headerHeight: number;
  };
  allowTextEdit?: boolean; // Enable text editing functionality
}

export const EditableFrame: React.FC<EditableFrameProps> = ({
  children,
  onPositionChange,
  onSizeChange,
  onTextChange,
  initialPosition = { x: 0, y: 0 },
  initialSize = { width: 200, height: 60 },
  initialText = '',
  isPinned: externalPinned = false,
  onPinChange,
  storageKey,
  boundaryConstraints = {
    leftMargin: window.innerWidth * 0.1,
    rightMargin: window.innerWidth * 0.1,
    headerHeight: Math.max(60, Math.min(120, window.innerHeight * 0.1))
  },
  allowTextEdit = false
}) => {
  const [isHovered, setIsHovered] = useState(false);
  const [isEditMode, setIsEditMode] = useState(false);
  const [isPinned, setIsPinned] = useState(externalPinned);
  const [position, setPosition] = useState(initialPosition);
  const [size, setSize] = useState(initialSize);
  const [isDragging, setIsDragging] = useState(false);
  const [isResizing, setIsResizing] = useState(false);
  const [resizeHandle, setResizeHandle] = useState('');
  const [dragStart, setDragStart] = useState({ x: 0, y: 0 });
  const [resizeStart, setResizeStart] = useState({ 
    x: 0, y: 0, width: 0, height: 0, 
    elementX: 0, elementY: 0 
  });
  const [hasBeenMoved, setHasBeenMoved] = useState(false);
  const [isAbsolutePositioned, setIsAbsolutePositioned] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [isTextEditing, setIsTextEditing] = useState(false);
  // Function to extract text from children
  const extractTextFromChildren = useCallback((children: React.ReactNode): string => {
    if (typeof children === 'string') {
      return children;
    }
    if (typeof children === 'number') {
      return children.toString();
    }
    if (React.isValidElement(children)) {
      if (children.props.children) {
        return extractTextFromChildren(children.props.children);
      }
    }
    if (Array.isArray(children)) {
      return children.map(extractTextFromChildren).join('');
    }
    return '';
  }, []);

  const [text, setText] = useState(initialText || extractTextFromChildren(children));

  const frameRef = useRef<HTMLDivElement>(null);

  // Update text when children change (if no initialText provided)
  useEffect(() => {
    if (!initialText) {
      const extractedText = extractTextFromChildren(children);
      if (extractedText && extractedText !== text) {
        setText(extractedText);
      }
    }
  }, [children, initialText, text, extractTextFromChildren]);

  // Load saved state from localStorage if storageKey is provided
  useEffect(() => {
    if (storageKey) {
      const savedPosition = localStorage.getItem(`${storageKey}_position`);
      const savedSize = localStorage.getItem(`${storageKey}_size`);
      const savedMoved = localStorage.getItem(`${storageKey}_moved`);
      const savedPinned = localStorage.getItem(`${storageKey}_pinned`);
      const savedText = localStorage.getItem(`${storageKey}_text`);

      if (savedPosition) {
        setPosition(JSON.parse(savedPosition));
        setHasBeenMoved(true);
        setIsAbsolutePositioned(true);
      }
      if (savedSize) {
        setSize(JSON.parse(savedSize));
      }
      if (savedMoved === 'true') {
        setHasBeenMoved(true);
      }
      if (savedPinned === 'true') {
        setIsPinned(true);
      }
      if (savedText) {
        setText(savedText);
      }
    }
    setIsLoading(false);
  }, [storageKey]);

  // Save state to localStorage whenever it changes
  useEffect(() => {
    if (storageKey) {
      localStorage.setItem(`${storageKey}_position`, JSON.stringify(position));
      localStorage.setItem(`${storageKey}_size`, JSON.stringify(size));
      localStorage.setItem(`${storageKey}_moved`, hasBeenMoved.toString());
      localStorage.setItem(`${storageKey}_pinned`, isPinned.toString());
      localStorage.setItem(`${storageKey}_text`, text);
    }
  }, [position, size, hasBeenMoved, isPinned, text, storageKey]);

  // Notify parent components of changes
  useEffect(() => {
    onPositionChange?.(position);
  }, [position, onPositionChange]);

  useEffect(() => {
    onSizeChange?.(size);
  }, [size, onSizeChange]);

  useEffect(() => {
    onPinChange?.(isPinned);
  }, [isPinned, onPinChange]);

  useEffect(() => {
    onTextChange?.(text);
  }, [text, onTextChange]);

  // Helper function to enforce boundary constraints
  const enforceBounds = useCallback((x: number, y: number, width: number, height: number) => {
    const leftMargin = boundaryConstraints.leftMargin;
    const rightMargin = boundaryConstraints.rightMargin;
    const headerHeight = boundaryConstraints.headerHeight;
    
    const maxX = window.innerWidth - rightMargin - width;
    const maxY = window.innerHeight - headerHeight - height;
    
    return {
      x: Math.max(leftMargin, Math.min(x, maxX)),
      y: Math.max(0, Math.min(y, maxY))
    };
  }, [boundaryConstraints]);

  // Handle mouse down for dragging
  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    if (!isEditMode || isPinned) return;
    
    e.preventDefault();
    setIsDragging(true);
    setDragStart({
      x: e.clientX - position.x,
      y: e.clientY - position.y
    });
  }, [isEditMode, isPinned, position]);

  // Handle mouse move for dragging and resizing
  const handleMouseMove = useCallback((e: MouseEvent) => {
    if (isDragging && isEditMode && !isPinned) {
      const newX = e.clientX - dragStart.x;
      const newY = e.clientY - dragStart.y;
      
      const constrainedPosition = enforceBounds(newX, newY, size.width, size.height);
      setPosition(constrainedPosition);
      
      if (!hasBeenMoved) {
        setHasBeenMoved(true);
      }
    }
    
    if (isResizing && isEditMode && !isPinned) {
      const deltaX = e.clientX - resizeStart.x;
      const deltaY = e.clientY - resizeStart.y;
      
      let newWidth = resizeStart.width;
      let newHeight = resizeStart.height;
      let newX = resizeStart.elementX;
      let newY = resizeStart.elementY;
      
      // Resize logic - keep opposite corner/edge fixed
      switch (resizeHandle) {
        case 'nw': // Top-left corner - keep bottom-right fixed
          newWidth = Math.max(50, resizeStart.width - deltaX);
          newHeight = Math.max(30, resizeStart.height - deltaY);
          newX = resizeStart.elementX + (resizeStart.width - newWidth);
          newY = resizeStart.elementY + (resizeStart.height - newHeight);
          break;
        case 'ne': // Top-right corner - keep bottom-left fixed
          newWidth = Math.max(50, resizeStart.width + deltaX);
          newHeight = Math.max(30, resizeStart.height - deltaY);
          newY = resizeStart.elementY + (resizeStart.height - newHeight);
          break;
        case 'sw': // Bottom-left corner - keep top-right fixed
          newWidth = Math.max(50, resizeStart.width - deltaX);
          newHeight = Math.max(30, resizeStart.height + deltaY);
          newX = resizeStart.elementX + (resizeStart.width - newWidth);
          break;
        case 'se': // Bottom-right corner - keep top-left fixed
          newWidth = Math.max(50, resizeStart.width + deltaX);
          newHeight = Math.max(30, resizeStart.height + deltaY);
          break;
        case 'n': // Top edge - keep bottom fixed
          newHeight = Math.max(30, resizeStart.height - deltaY);
          newY = resizeStart.elementY + (resizeStart.height - newHeight);
          break;
        case 's': // Bottom edge - keep top fixed
          newHeight = Math.max(30, resizeStart.height + deltaY);
          break;
        case 'w': // Left edge - keep right fixed
          newWidth = Math.max(50, resizeStart.width - deltaX);
          newX = resizeStart.elementX + (resizeStart.width - newWidth);
          break;
        case 'e': // Right edge - keep left fixed
          newWidth = Math.max(50, resizeStart.width + deltaX);
          break;
      }
      
      // Apply boundary constraints
      const constrainedPosition = enforceBounds(newX, newY, newWidth, newHeight);
      
      setSize({ width: newWidth, height: newHeight });
      setPosition({ x: constrainedPosition.x, y: constrainedPosition.y });
      
      if (!hasBeenMoved) {
        setHasBeenMoved(true);
      }
    }
  }, [isDragging, isResizing, isEditMode, isPinned, dragStart, resizeStart, size, resizeHandle, hasBeenMoved, enforceBounds]);

  // Handle mouse up
  const handleMouseUp = useCallback(() => {
    setIsDragging(false);
    setIsResizing(false);
    setResizeHandle('');
  }, []);

  // Add global event listeners
  useEffect(() => {
    if (isDragging || isResizing) {
      document.addEventListener('mousemove', handleMouseMove);
      document.addEventListener('mouseup', handleMouseUp);
      return () => {
        document.removeEventListener('mousemove', handleMouseMove);
        document.removeEventListener('mouseup', handleMouseUp);
      };
    }
  }, [isDragging, isResizing, handleMouseMove, handleMouseUp]);

  // Handle resize handle mouse down
  const handleResizeMouseDown = useCallback((e: React.MouseEvent, handle: string) => {
    if (!isEditMode || isPinned) return;
    
    e.preventDefault();
    e.stopPropagation();
    setIsResizing(true);
    setResizeHandle(handle);
    
    // Get current position from DOM element
    const frameRect = frameRef.current?.getBoundingClientRect();
    const currentX = frameRect ? frameRect.left : position.x;
    const currentY = frameRect ? frameRect.top : position.y;
    
    setResizeStart({
      x: e.clientX,
      y: e.clientY,
      width: size.width,
      height: size.height,
      elementX: currentX,
      elementY: currentY
    });
  }, [isEditMode, isPinned, size, position]);

  // Toggle edit mode
  const toggleEditMode = useCallback(() => {
    if (!isEditMode) {
      // Entering edit mode - capture current position and size from DOM
      const frameRect = frameRef.current?.getBoundingClientRect();
      if (frameRect) {
        const currentPos = {
          x: frameRect.left,
          y: frameRect.top
        };
        const currentSize = {
          width: frameRect.width,
          height: frameRect.height
        };
        setPosition(currentPos);
        setSize(currentSize);
      }
      setIsAbsolutePositioned(true);
    } else {
      // Exiting edit mode
      setIsDragging(false);
      setIsResizing(false);
      if (!hasBeenMoved) {
        setIsAbsolutePositioned(false);
      }
    }
    setIsEditMode(!isEditMode);
  }, [isEditMode, hasBeenMoved]);

  // Toggle pin
  const togglePin = useCallback(() => {
    setIsPinned(!isPinned);
  }, [isPinned]);

  // Toggle text editing
  const toggleTextEdit = useCallback(() => {
    setIsTextEditing(!isTextEditing);
  }, [isTextEditing]);

  // Handle text change
  const handleTextChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    setText(e.target.value);
  }, []);

  // Handle text edit key down
  const handleTextKeyDown = useCallback((e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      setIsTextEditing(false);
    } else if (e.key === 'Escape') {
      setIsTextEditing(false);
    }
  }, []);

  if (isLoading) {
    return <>{children}</>;
  }

  return (
    <div
      ref={frameRef}
      style={{
        position: isAbsolutePositioned ? 'absolute' : 'relative',
        left: isAbsolutePositioned ? `${position.x}px` : 'auto',
        top: isAbsolutePositioned ? `${position.y}px` : 'auto',
        width: isAbsolutePositioned ? `${size.width}px` : 'auto',
        height: isAbsolutePositioned ? `${size.height}px` : 'auto',
        border: isEditMode 
          ? '2px dashed rgba(255, 255, 255, 0.8)' 
          : isHovered 
            ? '2px solid rgba(255, 255, 255, 0.3)' 
            : '2px solid transparent',
        transition: isEditMode ? 'none' : 'all 0.2s ease',
        cursor: isEditMode && !isPinned ? 'move' : 'pointer',
        zIndex: isAbsolutePositioned ? 1001 : 'auto',
        display: 'inline-block',
        boxSizing: 'border-box'
      }}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
      onMouseDown={handleMouseDown}
    >
      {/* Content */}
      <div style={{
        width: '100%',
        height: '100%',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        pointerEvents: 'none',
        position: 'relative'
      }}>
        {children}
        {allowTextEdit && isTextEditing && (
          <input
            type="text"
            value={text}
            onChange={handleTextChange}
            onKeyDown={handleTextKeyDown}
            onBlur={() => setIsTextEditing(false)}
            style={{
              position: 'absolute',
              top: 0,
              left: 0,
              width: '100%',
              height: '100%',
              background: 'transparent',
              border: 'none',
              outline: 'none',
              color: 'inherit',
              fontSize: 'inherit',
              fontWeight: 'inherit',
              fontFamily: 'inherit',
              textAlign: 'center',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              pointerEvents: 'auto',
              zIndex: 1
            }}
            autoFocus
          />
        )}
      </div>
      
      {/* Resize Handles - Only show in edit mode */}
      {isEditMode && !isPinned && (
        <>
          {/* Corner handles */}
          <div
            style={{
              position: 'absolute',
              top: '-4px',
              left: '-4px',
              width: '8px',
              height: '8px',
              backgroundColor: 'rgba(255, 255, 255, 0.8)',
              border: '1px solid #000',
              cursor: 'nw-resize',
              zIndex: 10
            }}
            onMouseDown={(e) => handleResizeMouseDown(e, 'nw')}
          />
          <div
            style={{
              position: 'absolute',
              top: '-4px',
              right: '-4px',
              width: '8px',
              height: '8px',
              backgroundColor: 'rgba(255, 255, 255, 0.8)',
              border: '1px solid #000',
              cursor: 'ne-resize',
              zIndex: 10
            }}
            onMouseDown={(e) => handleResizeMouseDown(e, 'ne')}
          />
          <div
            style={{
              position: 'absolute',
              bottom: '-4px',
              left: '-4px',
              width: '8px',
              height: '8px',
              backgroundColor: 'rgba(255, 255, 255, 0.8)',
              border: '1px solid #000',
              cursor: 'sw-resize',
              zIndex: 10
            }}
            onMouseDown={(e) => handleResizeMouseDown(e, 'sw')}
          />
          <div
            style={{
              position: 'absolute',
              bottom: '-4px',
              right: '-4px',
              width: '8px',
              height: '8px',
              backgroundColor: 'rgba(255, 255, 255, 0.8)',
              border: '1px solid #000',
              cursor: 'se-resize',
              zIndex: 10
            }}
            onMouseDown={(e) => handleResizeMouseDown(e, 'se')}
          />
          
          {/* Edge handles */}
          <div
            style={{
              position: 'absolute',
              top: '-4px',
              left: '50%',
              transform: 'translateX(-50%)',
              width: '8px',
              height: '8px',
              backgroundColor: 'rgba(255, 255, 255, 0.8)',
              border: '1px solid #000',
              cursor: 'n-resize',
              zIndex: 10
            }}
            onMouseDown={(e) => handleResizeMouseDown(e, 'n')}
          />
          <div
            style={{
              position: 'absolute',
              bottom: '-4px',
              left: '50%',
              transform: 'translateX(-50%)',
              width: '8px',
              height: '8px',
              backgroundColor: 'rgba(255, 255, 255, 0.8)',
              border: '1px solid #000',
              cursor: 's-resize',
              zIndex: 10
            }}
            onMouseDown={(e) => handleResizeMouseDown(e, 's')}
          />
          <div
            style={{
              position: 'absolute',
              top: '50%',
              left: '-4px',
              transform: 'translateY(-50%)',
              width: '8px',
              height: '8px',
              backgroundColor: 'rgba(255, 255, 255, 0.8)',
              border: '1px solid #000',
              cursor: 'w-resize',
              zIndex: 10
            }}
            onMouseDown={(e) => handleResizeMouseDown(e, 'w')}
          />
          <div
            style={{
              position: 'absolute',
              top: '50%',
              right: '-4px',
              transform: 'translateY(-50%)',
              width: '8px',
              height: '8px',
              backgroundColor: 'rgba(255, 255, 255, 0.8)',
              border: '1px solid #000',
              cursor: 'e-resize',
              zIndex: 10
            }}
            onMouseDown={(e) => handleResizeMouseDown(e, 'e')}
          />
        </>
      )}
      
      {/* Control Buttons - Show on hover or in edit mode */}
      {(isHovered || isEditMode) && (
        <div style={{
          position: 'absolute',
          top: '-8px',
          right: '-8px',
          display: 'flex',
          gap: '4px',
          zIndex: 10
        }}>
          {/* Text Edit Button - Only show if text editing is enabled */}
          {allowTextEdit && (
            <button
              onClick={toggleTextEdit}
              style={{
                width: '24px',
                height: '24px',
                borderRadius: '4px',
                backgroundColor: isTextEditing ? '#ffffff' : 'rgba(255, 255, 255, 0.9)',
                border: 'none',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                cursor: 'pointer',
                transition: 'all 0.2s ease',
                boxShadow: '0 2px 4px rgba(0, 0, 0, 0.1)'
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.backgroundColor = '#ffffff';
                e.currentTarget.style.transform = 'scale(1.1)';
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.backgroundColor = isTextEditing ? '#ffffff' : 'rgba(255, 255, 255, 0.9)';
                e.currentTarget.style.transform = 'scale(1)';
              }}
              title={isTextEditing ? "Exit text edit" : "Edit text"}
            >
              <Type size={12} color="#000" />
            </button>
          )}
          
          {/* Edit Button */}
          <button
            onClick={toggleEditMode}
            style={{
              width: '24px',
              height: '24px',
              borderRadius: '4px',
              backgroundColor: isEditMode ? '#ffffff' : 'rgba(255, 255, 255, 0.9)',
              border: 'none',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              cursor: 'pointer',
              transition: 'all 0.2s ease',
              boxShadow: '0 2px 4px rgba(0, 0, 0, 0.1)'
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.backgroundColor = '#ffffff';
              e.currentTarget.style.transform = 'scale(1.1)';
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.backgroundColor = isEditMode ? '#ffffff' : 'rgba(255, 255, 255, 0.9)';
              e.currentTarget.style.transform = 'scale(1)';
            }}
            title={isEditMode ? "Exit edit mode" : "Edit element"}
          >
            {isEditMode ? <Move size={12} color="#000" /> : <Edit3 size={12} color="#000" />}
          </button>
          
          {/* Pin Button */}
          <button
            onClick={togglePin}
            style={{
              width: '24px',
              height: '24px',
              borderRadius: '4px',
              backgroundColor: isPinned ? '#ffffff' : 'rgba(255, 255, 255, 0.9)',
              border: 'none',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              cursor: 'pointer',
              transition: 'all 0.2s ease',
              boxShadow: '0 2px 4px rgba(0, 0, 0, 0.1)'
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.backgroundColor = '#ffffff';
              e.currentTarget.style.transform = 'scale(1.1)';
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.backgroundColor = isPinned ? '#ffffff' : 'rgba(255, 255, 255, 0.9)';
              e.currentTarget.style.transform = 'scale(1)';
            }}
            title={isPinned ? "Unpin element" : "Pin element"}
          >
            <Pin size={12} color={isPinned ? "#dc2626" : "#000"} />
          </button>
        </div>
      )}
    </div>
  );
};
