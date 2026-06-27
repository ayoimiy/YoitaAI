"""
Min-heap priority queue (cloned from YoitaAI files/scripts/utils/Heap.lua)

Stores (priority, value) tuples.  Lower priority floats to top.
"""


class MinHeap:
    def __init__(self):
        self.data = []  # list of [priority, value]

    def push(self, priority, value):
        """Insert a (priority, value) pair and bubble up."""
        d = self.data
        d.append([priority, value])
        i = len(d) - 1
        while i > 0:
            parent = (i - 1) // 2
            if d[parent][0] > d[i][0]:
                d[parent], d[i] = d[i], d[parent]
                i = parent
            else:
                break

    def pop(self):
        """Remove and return the value with smallest priority, or None if empty."""
        d = self.data
        if not d:
            return None
        top = d[0][1]
        last = d.pop()
        if d:
            d[0] = last
            i = 0
            n = len(d)
            while True:
                left = 2 * i + 1
                right = 2 * i + 2
                smallest = i
                if left < n and d[left][0] < d[smallest][0]:
                    smallest = left
                if right < n and d[right][0] < d[smallest][0]:
                    smallest = right
                if smallest == i:
                    break
                d[smallest], d[i] = d[i], d[smallest]
                i = smallest
        return top

    def peek(self):
        """Return the value with smallest priority without removing it."""
        if self.data:
            return self.data[0][1]
        return None

    def __len__(self):
        return len(self.data)

    def is_empty(self):
        return len(self.data) == 0
