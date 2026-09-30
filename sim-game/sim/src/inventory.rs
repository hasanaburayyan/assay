//! What a player is carrying: a list of item stacks.
//!
//! Stacks are kept sorted by item with no empty stacks, so two inventories
//! with the same contents are equal and hash the same however they were
//! filled. There is no capacity limit yet.

use serde::{Deserialize, Serialize};

use crate::item::{Item, ItemStack};

#[derive(Clone, Debug, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Inventory {
    stacks: Vec<ItemStack>,
}

impl Inventory {
    pub fn new() -> Self {
        Self::default()
    }

    /// Every stack, sorted by item, none empty.
    pub fn stacks(&self) -> &[ItemStack] {
        &self.stacks
    }

    pub fn count(&self, item: Item) -> u32 {
        self.stacks
            .iter()
            .find(|s| s.item == item)
            .map_or(0, |s| s.count)
    }

    pub fn has(&self, item: Item, count: u32) -> bool {
        self.count(item) >= count
    }

    pub fn is_empty(&self) -> bool {
        self.stacks.is_empty()
    }

    /// Items of every kind added together.
    pub fn total(&self) -> u32 {
        self.stacks.iter().map(|s| s.count).sum()
    }

    pub fn add(&mut self, item: Item, count: u32) {
        if count == 0 {
            return;
        }
        match self.stacks.binary_search_by_key(&item, |s| s.item) {
            Ok(i) => self.stacks[i].count = self.stacks[i].count.saturating_add(count),
            Err(i) => self.stacks.insert(i, ItemStack::new(item, count)),
        }
    }

    pub fn add_stack(&mut self, stack: ItemStack) {
        self.add(stack.item, stack.count);
    }

    /// Take `count` of `item`. All or nothing: returns `false` and changes
    /// nothing if there aren't enough.
    #[must_use]
    pub fn remove(&mut self, item: Item, count: u32) -> bool {
        let Ok(i) = self.stacks.binary_search_by_key(&item, |s| s.item) else {
            return count == 0;
        };
        if self.stacks[i].count < count {
            return false;
        }
        self.stacks[i].count -= count;
        if self.stacks[i].count == 0 {
            self.stacks.remove(i);
        }
        true
    }

    /// Take everything.
    pub fn drain(&mut self) -> Vec<ItemStack> {
        std::mem::take(&mut self.stacks)
    }
}
