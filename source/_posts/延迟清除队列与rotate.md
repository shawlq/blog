---
title: 延迟清除队列与rotate
date: 2019-01-08 22:24:28
categories: Distributed Develop
tags:
---

## 背景
记得很早之前学习c++11 API的时候，遇到过1个接口[std::rotate](https://zh.cppreference.com/w/cpp/algorithm/rotate)，当时不太能理解为什么要把容器整体移动一位，总觉得这种接口没有什么实际价值（事实上这个接口实现太通用，做了o(n)的移动操作，导致可用性降低）。

最近在工作中遇到个任务队列设计，要求从队列中取出任务对象，但是不要立即清除该对象在队列中的位置。由上层业务决定（上层会判断该任务是否需要等待，如果不等待才需要清除，否则仍旧保留在队列中。

综合一下诉求如下：

1. 提供获取任务的get接口，但是不立即从队列中清除；
2. 每次调用get接口都能获取下一个任务；
3. 上层执行任务后判断是否需要remove任务；
4. 上述操作性能不能太差；

## 第一印象：
这里不区分deque、list等容器的差异，线性容器统一使用list讨论设计方案。

第一反应，能想到的就是使用list，或者unoredered_map。
但为了追求高性能同时不想扩大存储内存，因而选择利用list的iterator，因为iter在新增、删除非本iter时不会失效。为了简单，我们让代码中的get接口直接返回iter（这里是为了示例，不对iter做封装）。

```c++
using Lock = std::lock_guard<std::mutex>;
template<typename F> class IterQueue {
    std::list<F> l_ ;
    std::mutex mtx_ ;
    typename std::list<F>::iterator pos;
public:
    IterQueue():pos(1_.end()){}
    
    void push(F&& fu) { Lock Lock(mtx_); 1_.empLace_back(std::forward<F>(fu)); }

    typename std::list<F>::iterator get() {
        Lock Lock(mtx_);
        /*省略1_为空场景处理*/
        if (pos == 1_.end()) {
            pos = 1_.begin();
        }
        return pos++;
    }

    void remove( typename std::list<F>::iterator it) {
        Lock Lock(mtx_);
        if (pos == it) pos = 1_.erase(it);
        else 1_.erase(it);
    }
}
```

这种方案的优点很明显，返回iter，如果上层要删除，传回iter，erase的性能是o(1)的。
其缺点同样也是显而易见：

* iter对外暴露（虽然可以进一步封装掉，也只是暴露的程度有别）;
* 同时对多线程的并发操作有约束，不能并发erase，否则可能会导致其它线程获取的iter失效。**这里之所以是可能，因为其它线程持有的iter不是erase的那个就不会失效**；


## 再想一想
上述方案使用iter其实有2个原因：

* 变更pos_，使得每次get都能获取到下一个；
* remove时不需要遍历，性能o(1)；

针对这2个因素，同样也可以考虑利用rotate特性来实现，源码如下

```c++
using Lock = std::lock_guard<std::mutex>;
template<typename F> class RotateQueue {
    std::list<F> l_ ;
    std::mutex mtx_ ;
public:
    void push(F&& fu) { Lock Lock(mtx_); 1_.emplace_front( std::forward<F>(fu)); }

    F get() {
        Lock Lock(mtx_ );
        1_.empLace_front(std::move(1_.back()));
        1_.pop_back();
        return l_.front();
    }
    
    void remove(const F& fu) {
        Lock Lock(mtx_ );
        for(auto i = l_.begin(); i != l_.end(); ++i) {
            if (fu == *i) {
                l_.erase(i);
                break;
            }
        }
    }
}
```

这样实现的优点很明显，不会暴露细节（iter）。
在get的时候，我们做了1次rotate，把list的back对象move到了front，并同时返回这个新front对象；
当上层remove这个对象的时候，因为是从begin开始的，这样就极大提升了找到的命中率。
当然这个性能提升也不是完美的，可以想象：
* 当上层单线程调用get/remove时，或者多线程，但是push的频率足够慢（慢于get --> remove的时间）时，remove的性能等价于o(1）;
* 但当上层多线程且push频率较高时，remove性能仍然趋向o(n)；

## 综合来看
### IterQueue：
* 更适合把实现嵌到上层代码中，这样iter可以作为上层对象的私有成员访问。
* 其次上层应用可以根据实际是否会存在多线程并发iter，进一步优化代码，做好保护。

### RotateQueue
* 可以独立为1个管理对象，同时在push频率显著低于 `get -> remove`时具有接近于IterQueue的性能。
* 但是对上层传入的对象有约束。要求对象的value不能相同，否则存在误删除问题。


```sequence
Thread1 ->> RotateQueue: get obj(value = 0x7fxxxxxx)
Thread2 ->> RotateQueue: get obj(value = 0x7fxxxxxx)
Thread1 ->> RotateQueue: remove obj(value = 0x7fxxxxxx)
Thread1 ->> RotateQueue: push new obj(value = 0x7fxxxxxx)
Thread2 -->> RotateQueue: remove obj(value = 0x7fxxxxxx)
Note left of Thread2 : the new pushed obj\nis unexpected removed!
```
```flow
```
